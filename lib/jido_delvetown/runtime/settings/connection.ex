defmodule JidoDelvetown.Settings.Connection do
  @moduledoc "Reads connection and local dashboard values from runtime settings."

  alias JidoDelvetown.Settings

  @type credentials :: %{identifier: String.t(), password: String.t()}
  @type dashboard :: %{enabled?: boolean(), port: pos_integer()}

  @spec credentials(keyword()) :: {:ok, credentials()} | {:error, term()}
  def credentials(opts \\ []) do
    with {:ok, identifier} <- required_value(:account_identifier, opts),
         {:ok, password_setting} <- Settings.fetch_secret(:account_app_password, opts),
         {:ok, password} <- required(:account_app_password, password_setting.value),
         :ok <- same_version(identifier.version, password_setting.version) do
      {:ok, %{identifier: identifier.value, password: password}}
    end
  end

  @spec credentials_configured?(keyword()) :: boolean()
  def credentials_configured?(opts \\ []), do: match?({:ok, _credentials}, credentials(opts))

  @spec pds_url(keyword()) :: {:ok, String.t()} | {:error, term()}
  def pds_url(opts \\ []), do: value(:pds_url, opts)

  @spec appview_did(keyword()) :: {:ok, String.t()} | {:error, term()}
  def appview_did(opts \\ []), do: value(:appview_did, opts)

  @spec proxy_header(keyword()) :: {:ok, String.t()} | {:error, term()}
  def proxy_header(opts \\ []) do
    with {:ok, appview_did} <- appview_did(opts) do
      {:ok, "#{appview_did}#bsky_appview"}
    end
  end

  @spec dashboard(keyword()) :: {:ok, dashboard()} | {:error, term()}
  def dashboard(opts \\ []) do
    with {:ok, settings} <- Settings.current(opts) do
      {:ok,
       %{
         enabled?: settings.values.dashboard_enabled,
         port: settings.values.dashboard_port
       }}
    end
  end

  defp required_value(key, opts) do
    with {:ok, setting} <- Settings.fetch(key, opts),
         {:ok, _value} <- required(key, setting.value) do
      {:ok, setting}
    end
  end

  defp value(key, opts) do
    with {:ok, setting} <- Settings.fetch(key, opts) do
      {:ok, setting.value}
    end
  end

  defp required(key, value) when value in [nil, ""],
    do: {:error, {:connection_setting_missing, key}}

  defp required(_key, value), do: {:ok, value}

  defp same_version(version, version), do: :ok

  defp same_version(first, second),
    do: {:error, {:connection_settings_changed, first, second}}
end
