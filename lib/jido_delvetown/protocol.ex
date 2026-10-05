defmodule JidoDelvetown.Protocol do
  @moduledoc "Safe protocol operations used by the hard-coded Jido tools."

  alias JidoDelvetown.Config
  alias JidoDelvetown.Session
  alias JidoDelvetown.Store
  alias JidoDelvetown.Transport.ProtoRune, as: DefaultTransport

  @allowed_collections [
    "town.delve.feed.post",
    "town.delve.feed.like",
    "town.delve.feed.repost",
    "town.delve.graph.follow"
  ]

  def query(method, params) when is_binary(method) and is_map(params) do
    with {:ok, session} <- session_module().session() do
      result = transport().appview_query(session, method, compact(params), [])
      audit(:query, %{method: method, result: outcome(result)})
      result
    end
  end

  def procedure(method, body) when is_binary(method) and is_map(body) do
    with :ok <- writes_enabled(),
         {:ok, session} <- session_module().session() do
      result = transport().appview_procedure(session, method, compact(body), [])
      audit(:procedure, %{method: method, result: outcome(result)})
      result
    end
  end

  def notification_procedure(method, body) when is_binary(method) and is_map(body) do
    with :ok <- notification_updates_enabled(),
         {:ok, session} <- session_module().session() do
      result = transport().appview_procedure(session, method, compact(body), [])
      audit(:notification_procedure, %{method: method, result: outcome(result)})
      result
    end
  end

  def list_own_records(collection, params) when is_binary(collection) and is_map(params) do
    with :ok <- allowed_collection(collection),
         {:ok, session} <- session_module().session() do
      result = transport().list_records(session, collection, compact(params), [])
      audit(:list_records, %{collection: collection, result: outcome(result)})
      result
    end
  end

  def create_record(effect_key, collection, record)
      when is_binary(effect_key) and is_binary(collection) and is_map(record) do
    with :ok <- writes_enabled(),
         :ok <- allowed_collection(collection),
         {:ok, session} <- session_module().session(),
         {:ok, effect} <- Store.reserve_effect(effect_key, collection, store()) do
      create_or_reuse(session, effect, record)
    end
  end

  def delete_own_record(uri) when is_binary(uri) do
    with :ok <- writes_enabled(),
         {:ok, session} <- session_module().session(),
         {:ok, repo, collection, rkey} <- parse_at_uri(uri),
         :ok <- own_repo(session, repo),
         :ok <- allowed_collection(collection) do
      case transport().delete_record(session, collection, rkey, []) do
        {:ok, _receipt} = result ->
          audit(:delete_record, %{collection: collection, rkey: rkey, result: :ok})
          result

        {:error, delete_error} ->
          reconcile_delete(session, collection, rkey, delete_error)
      end
    end
  end

  def effect_key(kind, values) when is_binary(kind) and is_list(values) do
    digest =
      values
      |> Enum.join("\u001F")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    kind <> ":" <> digest
  end

  def now, do: DateTime.utc_now() |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()
  def allowed_collections, do: @allowed_collections

  defp create_or_reuse(_session, %{status: :complete} = effect, _record) do
    {:ok, %{receipt: effect.receipt, reused?: true, reconciled?: false}}
  end

  defp create_or_reuse(session, effect, record) do
    record = Map.put(record, "$type", effect.collection)

    case transport().create_record(session, effect.collection, record, effect.rkey, []) do
      {:ok, receipt} ->
        complete_create(effect, receipt, false)

      {:error, create_error} ->
        reconcile_create(session, effect, create_error)
    end
  end

  defp reconcile_create(session, effect, create_error) do
    case transport().get_record(session, effect.collection, effect.rkey, []) do
      {:ok, receipt} ->
        complete_create(effect, receipt, true)

      {:error, lookup_error} ->
        audit(:create_record, %{
          collection: effect.collection,
          rkey: effect.rkey,
          result: :error
        })

        {:error,
         {:create_failed, safe_reason(create_error), safe_reason(lookup_error), effect.rkey}}
    end
  end

  defp complete_create(effect, receipt, reconciled?) do
    with {:ok, _effect} <- Store.complete_effect(effect.key, receipt, store()) do
      audit(:create_record, %{
        collection: effect.collection,
        rkey: effect.rkey,
        record_uri: receipt_uri(receipt),
        result: :ok,
        reconciled?: reconciled?
      })

      {:ok, %{receipt: receipt, reused?: false, reconciled?: reconciled?}}
    end
  end

  defp reconcile_delete(session, collection, rkey, delete_error) do
    case transport().get_record(session, collection, rkey, []) do
      {:error, reason} when is_struct(reason, ProtoRune.XRPC.Error) ->
        if reason.http_status == 404 do
          audit(:delete_record, %{collection: collection, rkey: rkey, result: :reconciled})
          {:ok, %{deleted?: true, reconciled?: true}}
        else
          {:error, {:delete_failed, safe_reason(delete_error), safe_reason(reason)}}
        end

      {:error, lookup_error} ->
        {:error, {:delete_failed, safe_reason(delete_error), safe_reason(lookup_error)}}

      {:ok, _record} ->
        {:error, {:delete_failed, safe_reason(delete_error), :record_still_exists}}
    end
  end

  defp parse_at_uri(uri) do
    case Regex.run(~r{\Aat://([^/]+)/([^/]+)/([^/]+)\z}, uri, capture: :all_but_first) do
      [repo, collection, rkey] -> {:ok, repo, collection, rkey}
      _other -> {:error, :invalid_at_uri}
    end
  end

  defp own_repo(session, repo) do
    if ProtoRune.Session.did(session) == repo, do: :ok, else: {:error, :record_not_owned}
  end

  defp allowed_collection(collection) do
    if collection in @allowed_collections,
      do: :ok,
      else: {:error, {:collection_not_allowed, collection}}
  end

  defp writes_enabled do
    if Config.write_enabled?(), do: :ok, else: {:error, :writes_disabled}
  end

  defp notification_updates_enabled do
    if Config.mark_notifications_seen?(),
      do: :ok,
      else: {:error, :notification_updates_disabled}
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp safe_reason(%ProtoRune.XRPC.Error{} = error) do
    Map.take(error, [:reason, :message, :http_status, :retry_after])
  end

  defp safe_reason(reason) when is_atom(reason) or is_binary(reason), do: reason
  defp safe_reason(_reason), do: :transport_error

  defp outcome({:ok, _value}), do: :ok
  defp outcome({:error, _reason}), do: :error

  defp receipt_uri(%{uri: uri}) when is_binary(uri), do: uri
  defp receipt_uri(%{"uri" => uri}) when is_binary(uri), do: uri
  defp receipt_uri(_receipt), do: nil

  defp audit(type, data) do
    _result = Store.add_event(type, data, store())
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp session_module,
    do: Application.get_env(:jido_delvetown, :session_module, Session)

  defp transport,
    do: Application.get_env(:jido_delvetown, :transport, DefaultTransport)

  defp store,
    do: Application.get_env(:jido_delvetown, :store, Store)
end
