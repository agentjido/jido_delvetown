defmodule JidoDelvetown.Config do
  @moduledoc false

  @default_pds_url "https://pds.delve.town"
  @default_appview_did "did:web:api.delve.town"
  @default_model "openai:gpt-4o-mini"
  @default_data_dir Path.expand("../../tmp/jido_delvetown", __DIR__)

  def load_env(path \\ ".env") do
    if File.regular?(path) do
      System.put_env(Dotenvy.source!([path, System.get_env()], side_effect: nil))
    end

    :ok
  end

  def pds_url, do: System.get_env("DELVETOWN_PDS_URL", @default_pds_url)
  def appview_did, do: System.get_env("DELVETOWN_APPVIEW_DID", @default_appview_did)
  def proxy_header, do: "#{appview_did()}#bsky_appview"
  def decision_model, do: System.get_env("DELVETOWN_MODEL", @default_model)

  def decision_model_input(model \\ decision_model())

  def decision_model_input("openai:" <> model) do
    %{
      id: model,
      model: model,
      provider: :openai,
      base_url: "https://api.openai.com/v1",
      deprecated: false,
      retired: false,
      catalog_only: false,
      aliases: []
    }
  end

  def decision_model_input(model), do: model

  def dashboard_enabled? do
    case System.get_env("DELVETOWN_DASHBOARD_ENABLED") do
      nil -> Application.get_env(:jido_delvetown, :dashboard_enabled, true)
      value -> enabled_value?(value)
    end
  end

  def dashboard_port do
    env_integer("DELVETOWN_DASHBOARD_PORT", 4040, 1, 65_535)
  end

  def decision_timeout do
    env_integer("DELVETOWN_DECISION_TIMEOUT_MS", 45_000, 1_000, 180_000)
  end

  def notification_limit do
    env_integer("DELVETOWN_NOTIFICATION_LIMIT", 20, 1, 100)
  end

  def daily_reply_limit do
    env_integer("DELVETOWN_DAILY_REPLY_LIMIT", 3, 0, 100)
  end

  def daily_welcome_limit do
    env_integer("DELVETOWN_DAILY_WELCOME_LIMIT", 2, 0, 100)
  end

  def member_discovery_limit do
    env_integer("DELVETOWN_MEMBER_DISCOVERY_LIMIT", 20, 1, 100)
  end

  def member_max_age_hours do
    env_integer("DELVETOWN_MEMBER_MAX_AGE_HOURS", 24, 1, 24 * 30)
  end

  def conversation_turn_limit do
    env_integer("DELVETOWN_CONVERSATION_TURN_LIMIT", 4, 1, 100)
  end

  def conversation_max_age_hours do
    env_integer("DELVETOWN_CONVERSATION_MAX_AGE_HOURS", 72, 1, 24 * 365)
  end

  def conversation_non_response_limit do
    env_integer("DELVETOWN_CONVERSATION_NON_RESPONSE_LIMIT", 2, 1, 20)
  end

  def write_enabled? do
    enabled?("DELVETOWN_WRITE_ENABLED")
  end

  def manual_publish_enabled? do
    enabled?("DELVETOWN_MANUAL_PUBLISH_ENABLED")
  end

  def dry_run_mark_actioned? do
    enabled?("DELVETOWN_DRY_RUN_MARK_ACTIONED")
  end

  def mark_notifications_seen?,
    do: enabled?("DELVETOWN_MARK_NOTIFICATIONS_SEEN")

  def data_dir,
    do: System.get_env("DELVETOWN_DATA_DIR", @default_data_dir) |> Path.expand()

  def database_path do
    System.get_env("DELVETOWN_DATABASE_PATH") ||
      Application.get_env(
        :jido_delvetown,
        :database_path,
        Path.join(data_dir(), "jido_delvetown.sqlite3")
      )
      |> Path.expand()
  end

  def legacy_import_enabled? do
    case System.get_env("DELVETOWN_LEGACY_IMPORT_ENABLED") do
      nil -> Application.get_env(:jido_delvetown, :legacy_import_enabled, true)
      value -> enabled_value?(value)
    end
  end

  def legacy_checkpoint_path, do: Path.join(data_dir(), "jido_checkpoints")
  def legacy_state_path, do: Path.join(data_dir(), "delvetown_state.dets")

  def credentials do
    with {:ok, identifier} <- fetch_env("DELVETOWN_IDENTIFIER"),
         {:ok, password} <- fetch_env("DELVETOWN_APP_PASSWORD") do
      {:ok, %{identifier: identifier, password: password}}
    end
  end

  def invite_code, do: fetch_env("DELVETOWN_INVITE_CODE")

  defp fetch_env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_environment_variable, name}}
    end
  end

  defp env_integer(name, default, minimum, maximum) do
    value =
      case Integer.parse(System.get_env(name, "")) do
        {integer, ""} -> integer
        _other -> default
      end

    value |> max(minimum) |> min(maximum)
  end

  defp enabled?(name) do
    name
    |> System.get_env("false")
    |> enabled_value?()
  end

  defp enabled_value?(value), do: String.downcase(value) in ["1", "true", "yes"]
end
