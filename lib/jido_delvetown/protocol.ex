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

  @doc false
  def upload_blob(bytes, mime_type) when is_binary(bytes) and is_binary(mime_type) do
    with :ok <- writes_enabled(),
         {:ok, session} <- session_module().session() do
      result = transport().upload_blob(session, bytes, mime_type, [])

      audit(:upload_blob, %{
        mime_type: mime_type,
        byte_size: byte_size(bytes),
        result: outcome(result)
      })

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

  def create_record(effect_key, collection, record, opts \\ [])
      when is_binary(effect_key) and is_binary(collection) and is_map(record) and
             is_list(opts) do
    with :ok <- writes_enabled(),
         {:ok, result} <- create_record_with_effect(effect_key, collection, record, opts) do
      {:ok, result}
    end
  end

  def create_manual_record(effect_key, collection, record, opts \\ [])
      when is_binary(effect_key) and is_binary(collection) and is_map(record) and
             is_list(opts) do
    with :ok <- manual_publish_enabled(),
         {:ok, result} <- create_record_with_effect(effect_key, collection, record, opts) do
      {:ok, result}
    end
  end

  defp create_record_with_effect(effect_key, collection, record, opts) do
    with :ok <- allowed_collection(collection),
         {:ok, session} <- session_module().session(),
         {:ok, effect} <-
           Store.reserve_effect(effect_key, collection, effect_attributes(opts), store()) do
      create_or_reuse(session, effect, record)
    end
  end

  def delete_own_record(uri) when is_binary(uri) do
    with :ok <- writes_enabled(),
         {:ok, session} <- session_module().session(),
         {:ok, repo, collection, rkey} <- parse_at_uri(uri),
         :ok <- own_repo(session, repo),
         :ok <- allowed_collection(collection),
         effect_key = effect_key("delete", [uri]),
         {:ok, effect} <-
           Store.reserve_effect(
             effect_key,
             collection,
             %{rkey: rkey, subject_key: uri},
             store()
           ) do
      delete_or_reuse(session, effect)
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

  @doc false
  def ensure_writes_enabled, do: writes_enabled()

  defp create_or_reuse(_session, %{status: :completed} = effect, _record) do
    {:ok, %{receipt: effect.receipt, reused?: true, reconciled?: false}}
  end

  defp create_or_reuse(_session, %{status: :permanent_failure} = effect, _record) do
    {:error, {:effect_failed_permanently, effect.failure}}
  end

  defp create_or_reuse(session, %{status: :uncertain} = effect, record) do
    case reconcile_existing_create(session, effect) do
      {:ok, result} -> {:ok, result}
      :missing -> attempt_create(session, effect, record)
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_or_reuse(session, %{status: :reserved} = effect, record),
    do: attempt_create(session, effect, record)

  defp attempt_create(session, effect, record) do
    record = Map.put(record, "$type", effect.collection)

    with {:ok, attempted} <- Store.begin_effect_attempt(effect.key, store()) do
      create_once(session, attempted, record)
    end
  end

  defp create_once(session, effect, record) do
    case transport().create_record(session, effect.collection, record, effect.rkey, []) do
      {:ok, receipt} ->
        complete_create(effect, receipt, false)

      {:error, create_error} ->
        if permanent_error?(create_error) do
          fail_create_permanently(effect, create_error)
        else
          reconcile_create(session, effect, create_error)
        end
    end
  end

  defp reconcile_existing_create(session, effect) do
    case transport().get_record(session, effect.collection, effect.rkey, []) do
      {:ok, receipt} ->
        case complete_create(effect, receipt, true) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        if not_found?(reason),
          do: :missing,
          else: {:error, {:reconcile_failed, safe_reason(reason), effect.rkey}}
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

        if not_found?(lookup_error) do
          {:error, {:create_uncertain, safe_reason(create_error), effect.rkey}}
        else
          {:error,
           {:create_failed, safe_reason(create_error), safe_reason(lookup_error), effect.rkey}}
        end
    end
  end

  defp fail_create_permanently(effect, create_error) do
    failure = %{operation: :create, reason: safe_reason(create_error)}

    with {:ok, _failed} <- Store.fail_effect_permanently(effect.key, failure, store()) do
      audit(:create_record, %{
        collection: effect.collection,
        rkey: effect.rkey,
        result: :permanent_failure
      })

      {:error, {:create_failed_permanently, safe_reason(create_error)}}
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

  defp delete_or_reuse(_session, %{status: :completed} = effect) do
    {:ok, %{receipt: effect.receipt, deleted?: true, reused?: true, reconciled?: false}}
  end

  defp delete_or_reuse(_session, %{status: :permanent_failure} = effect) do
    {:error, {:effect_failed_permanently, effect.failure}}
  end

  defp delete_or_reuse(session, %{status: :uncertain} = effect) do
    case transport().get_record(session, effect.collection, effect.rkey, []) do
      {:ok, _record} -> attempt_delete(session, effect)
      {:error, reason} when reason == :not_found -> complete_delete(effect, true)
      {:error, %ProtoRune.XRPC.Error{http_status: 404}} -> complete_delete(effect, true)
      {:error, reason} -> {:error, {:reconcile_failed, safe_reason(reason), effect.rkey}}
    end
  end

  defp delete_or_reuse(session, %{status: :reserved} = effect),
    do: attempt_delete(session, effect)

  defp attempt_delete(session, effect) do
    with {:ok, attempted} <- Store.begin_effect_attempt(effect.key, store()) do
      case transport().delete_record(session, attempted.collection, attempted.rkey, []) do
        {:ok, receipt} ->
          complete_delete(attempted, false, receipt)

        {:error, delete_error} ->
          reconcile_delete(session, attempted, delete_error)
      end
    end
  end

  defp reconcile_delete(session, effect, delete_error) do
    case transport().get_record(session, effect.collection, effect.rkey, []) do
      {:error, reason} ->
        cond do
          not_found?(reason) ->
            complete_delete(effect, true)

          permanent_error?(delete_error) ->
            fail_delete_permanently(effect, delete_error)

          true ->
            {:error, {:delete_failed, safe_reason(delete_error), safe_reason(reason)}}
        end

      {:ok, _record} ->
        if permanent_error?(delete_error) do
          fail_delete_permanently(effect, delete_error)
        else
          {:error, {:delete_uncertain, safe_reason(delete_error), effect.rkey}}
        end
    end
  end

  defp complete_delete(effect, reconciled?, receipt \\ %{}) do
    saved_receipt = %{deleted: true, remote: receipt}

    with {:ok, _effect} <- Store.complete_effect(effect.key, saved_receipt, store()) do
      audit(:delete_record, %{
        collection: effect.collection,
        rkey: effect.rkey,
        result: :ok,
        reconciled?: reconciled?
      })

      {:ok, %{receipt: saved_receipt, deleted?: true, reused?: false, reconciled?: reconciled?}}
    end
  end

  defp fail_delete_permanently(effect, delete_error) do
    failure = %{operation: :delete, reason: safe_reason(delete_error)}

    with {:ok, _failed} <- Store.fail_effect_permanently(effect.key, failure, store()) do
      audit(:delete_record, %{
        collection: effect.collection,
        rkey: effect.rkey,
        result: :permanent_failure
      })

      {:error, {:delete_failed_permanently, safe_reason(delete_error)}}
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

  defp manual_publish_enabled do
    if Config.manual_publish_enabled?(),
      do: :ok,
      else: {:error, :manual_publish_disabled}
  end

  defp notification_updates_enabled do
    if Config.mark_notifications_seen?(),
      do: :ok,
      else: {:error, :notification_updates_disabled}
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp effect_attributes(opts) do
    opts
    |> Keyword.take([:subject_key, :actor_did, :rkey])
    |> Map.new()
  end

  defp not_found?(:not_found), do: true
  defp not_found?(%ProtoRune.XRPC.Error{http_status: 404}), do: true
  defp not_found?(_reason), do: false

  defp permanent_error?(%ProtoRune.XRPC.Error{http_status: status})
       when status >= 400 and status < 500 and status not in [408, 429],
       do: true

  defp permanent_error?(_reason), do: false

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
