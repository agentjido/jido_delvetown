defmodule JidoDelvetown.Transport.ProtoRune do
  @moduledoc "Delvetown AT Protocol operations implemented with ProtoRune."

  @behaviour JidoDelvetown.Transport

  alias JidoDelvetown.Settings.Connection
  alias ProtoRune.Atproto.Repo
  alias ProtoRune.Atproto.Session, as: AtprotoSession
  alias ProtoRune.Session
  alias ProtoRune.XRPC.Client
  alias ProtoRune.XRPC.Procedure
  alias ProtoRune.XRPC.Query

  @profile_collection "town.delve.actor.profile"

  @impl true
  def login(identifier, password, opts \\ []) do
    with {:ok, service} <- configured_service(opts) do
      ProtoRune.login(identifier, password,
        service: service,
        http: Keyword.get(opts, :http, [])
      )
    end
  end

  @impl true
  def list_notifications(session, opts \\ []) do
    params =
      %{limit: Keyword.get(opts, :limit, 50), cursor: Keyword.get(opts, :cursor)}
      |> reject_nil_values()

    appview_query(session, "town.delve.notification.listNotifications", params, opts)
  end

  @impl true
  def get_post_thread(session, uri, opts \\ []) do
    appview_query(
      session,
      "town.delve.feed.getPostThread",
      %{uri: uri, depth: Keyword.get(opts, :depth, 12), parent_height: 12},
      opts
    )
  end

  @impl true
  def get_membership(session, opts \\ []) do
    appview_query(session, "town.delve.membership.getMembership", %{}, opts)
  end

  @impl true
  def join(session, invite_code, opts \\ []) do
    body = if invite_code in [nil, ""], do: %{}, else: %{invite_code: invite_code}
    appview_procedure(session, "town.delve.membership.join", body, opts)
  end

  @impl true
  def get_record(session, collection, rkey, opts \\ []) do
    Repo.get_record(
      session,
      %{repo: Session.did(session), collection: collection, rkey: rkey},
      http: Keyword.get(opts, :http, [])
    )
  end

  @impl true
  def create_record(session, collection, record, rkey, opts \\ []) do
    Repo.create_record(
      session,
      %{repo: Session.did(session), collection: collection, rkey: rkey, record: record},
      http: Keyword.get(opts, :http, [])
    )
  end

  @impl true
  def list_records(session, collection, params, opts \\ []) do
    Repo.list_records(
      session,
      params
      |> Map.put(:repo, Session.did(session))
      |> Map.put(:collection, collection),
      http: Keyword.get(opts, :http, [])
    )
  end

  @impl true
  def delete_record(session, collection, rkey, opts \\ []) do
    Repo.delete_record(
      session,
      %{repo: Session.did(session), collection: collection, rkey: rkey},
      http: Keyword.get(opts, :http, [])
    )
  end

  @impl true
  def upload_blob(session, bytes, mime_type, opts \\ []) do
    Repo.upload_blob(session, bytes, mime_type, http: Keyword.get(opts, :http, []))
  end

  @impl true
  def label_bot(session, description, opts \\ []) do
    with {:ok, record} <- current_profile(session, opts) do
      labels = bot_labels(value(record, :labels))

      profile =
        record
        |> Map.drop([:"$type", "$type"])
        |> Map.put("$type", @profile_collection)
        |> Map.put(:description, description)
        |> Map.put(:labels, labels)

      Repo.put_record(
        session,
        %{
          repo: Session.did(session),
          collection: @profile_collection,
          rkey: "self",
          record: profile
        },
        http: Keyword.get(opts, :http, [])
      )
    end
  end

  defp current_profile(session, opts) do
    case Repo.get_record(
           session,
           %{repo: Session.did(session), collection: @profile_collection, rkey: "self"},
           http: Keyword.get(opts, :http, [])
         ) do
      {:ok, response} -> {:ok, value(response, :value) || %{}}
      {:error, %ProtoRune.XRPC.Error{http_status: 404}} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp bot_labels(nil) do
    %{"$type" => "com.atproto.label.defs#selfLabels", values: [%{val: "bot"}]}
  end

  defp bot_labels(labels) when is_map(labels) do
    values = value(labels, :values) || []

    values =
      if Enum.any?(values, &(value(&1, :val) == "bot")),
        do: values,
        else: values ++ [%{val: "bot"}]

    labels
    |> Map.drop([:"$type", "$type"])
    |> Map.put("$type", "com.atproto.label.defs#selfLabels")
    |> Map.put(:values, values)
  end

  @impl true
  def appview_query(session, method, params, opts \\ []) do
    with {:ok, base_url} <- service_url(session),
         {:ok, proxy_header} <- Connection.proxy_header(),
         unsigned_url = Path.join(base_url, method),
         query = %{
           Query.new(method, base_url: base_url)
           | params: encode_query_params(params)
         },
         {:ok, headers, session} <- Session.authorization_headers(session, "GET", unsigned_url) do
      query
      |> Query.put_header("atproto-proxy", proxy_header)
      |> then(&%{&1 | headers: Map.merge(&1.headers, headers)})
      |> Client.execute(session: session, http: Keyword.get(opts, :http, []))
    end
  end

  @impl true
  def appview_procedure(session, method, body, opts \\ []) do
    with {:ok, base_url} <- service_url(session),
         {:ok, proxy_header} <- Connection.proxy_header(),
         url = Path.join(base_url, method),
         {:ok, headers, session} <- Session.authorization_headers(session, "POST", url) do
      method
      |> Procedure.new(base_url: base_url)
      |> then(&%{&1 | body: body})
      |> Procedure.put_header("atproto-proxy", proxy_header)
      |> then(&%{&1 | headers: Map.merge(&1.headers, headers)})
      |> Client.execute(session: session, http: Keyword.get(opts, :http, []))
    end
  end

  defp configured_service(opts) do
    case Keyword.fetch(opts, :service) do
      {:ok, service} -> {:ok, service}
      :error -> Connection.pds_url()
    end
  end

  defp service_url(session) do
    case Session.service_url(session) do
      service when is_binary(service) and service != "" ->
        {:ok, service}

      _missing ->
        with {:ok, service} <- Connection.pds_url() do
          {:ok, AtprotoSession.normalize_service_url(service)}
        end
    end
  end

  defp reject_nil_values(map), do: Map.reject(map, fn {_key, item} -> is_nil(item) end)

  defp encode_query_params(params) do
    params
    |> ProtoRune.Case.camelize_enum()
    |> Enum.flat_map(fn
      {key, values} when is_list(values) -> Enum.map(values, &{key, &1})
      pair -> [pair]
    end)
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
