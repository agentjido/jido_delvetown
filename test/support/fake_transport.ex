defmodule JidoDelvetown.Test.FakeTransport do
  @moduledoc false

  @behaviour JidoDelvetown.Transport

  @impl true
  def login(_identifier, _password, _opts), do: result(:login_result, {:error, :not_configured})

  @impl true
  def list_notifications(_session, _opts), do: result(:list_notifications_result, {:ok, %{}})

  @impl true
  def get_post_thread(_session, _uri, _opts), do: result(:get_post_thread_result, {:ok, %{}})

  @impl true
  def get_membership(_session, _opts), do: result(:get_membership_result, {:ok, %{}})

  @impl true
  def join(_session, _invite_code, _opts), do: result(:join_result, {:ok, %{}})

  @impl true
  def label_bot(_session, _description, _opts), do: result(:label_bot_result, {:ok, %{}})

  @impl true
  def appview_query(_session, method, params, _opts) do
    notify({:appview_query, method, params})

    case Application.get_env(:jido_delvetown, :query_results, %{}) do
      %{^method => configured} -> configured
      _results -> result(:query_result, {:ok, %{}})
    end
  end

  @impl true
  def appview_procedure(_session, method, body, _opts) do
    notify({:appview_procedure, method, body})
    result(:procedure_result, {:ok, %{}})
  end

  @impl true
  def upload_blob(_session, bytes, mime_type, _opts) do
    notify({:upload_blob, bytes, mime_type})
    result(:upload_blob_result, {:error, :not_configured})
  end

  @impl true
  def create_record(_session, collection, record, rkey, _opts) do
    notify({:create_record, collection, record, rkey})
    result(:create_result, {:ok, %{uri: "at://did:plc:bot/#{collection}/#{rkey}", cid: "cid"}})
  end

  @impl true
  def get_record(_session, collection, rkey, _opts) do
    notify({:get_record, collection, rkey})
    result(:get_result, {:error, :not_found})
  end

  @impl true
  def list_records(_session, collection, params, _opts) do
    notify({:list_records, collection, params})
    result(:list_records_result, {:ok, %{records: []}})
  end

  @impl true
  def delete_record(_session, collection, rkey, _opts) do
    notify({:delete_record, collection, rkey})
    result(:delete_result, {:ok, %{}})
  end

  defp result(key, default), do: Application.get_env(:jido_delvetown, key, default)

  defp notify(message) do
    if owner = Application.get_env(:jido_delvetown, :test_owner), do: send(owner, message)
    :ok
  end
end

defmodule JidoDelvetown.Test.HTTPAdapter do
  @moduledoc false

  @behaviour ProtoRune.HTTPClient.Adapter

  @impl true
  def request(method, url, opts) do
    send(Application.fetch_env!(:jido_delvetown, :test_owner), {:http_request, method, url, opts})
    {:ok, %{status: 200, headers: [{"content-type", "application/json"}], body: "{}"}}
  end
end
