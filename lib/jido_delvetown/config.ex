defmodule JidoDelvetown.Config do
  @moduledoc false

  @default_data_dir Path.expand("../../tmp/jido_delvetown", __DIR__)

  def load_env(path \\ ".env") do
    if File.regular?(path) do
      System.put_env(Dotenvy.source!([path, System.get_env()], side_effect: nil))
    end

    :ok
  end

  def notification_limit do
    env_integer("DELVETOWN_NOTIFICATION_LIMIT", 20, 1, 100)
  end

  def daily_reply_limit do
    env_integer("DELVETOWN_DAILY_REPLY_LIMIT", 3, 0, 100)
  end

  def daily_like_limit do
    env_integer("DELVETOWN_DAILY_LIKE_LIMIT", 5, 0, 100)
  end

  def like_actor_cooldown_hours do
    env_integer("DELVETOWN_LIKE_ACTOR_COOLDOWN_HOURS", 24, 1, 24 * 30)
  end

  def like_candidate_max_age_hours do
    env_integer("DELVETOWN_LIKE_CANDIDATE_MAX_AGE_HOURS", 48, 1, 24 * 30)
  end

  def daily_welcome_limit do
    env_integer("DELVETOWN_DAILY_WELCOME_LIMIT", 2, 0, 100)
  end

  def member_discovery_limit do
    env_integer("DELVETOWN_MEMBER_DISCOVERY_LIMIT", 20, 1, 100)
  end

  def friend_sync_limit do
    env_integer("DELVETOWN_FRIEND_SYNC_LIMIT", 1_000, 1, 10_000)
  end

  def member_max_age_hours do
    env_integer("DELVETOWN_MEMBER_MAX_AGE_HOURS", 24, 1, 24 * 30)
  end

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

  def settings_key_path do
    Application.get_env(
      :jido_delvetown,
      :settings_key_path,
      database_path() <> ".settings.key"
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

  defp enabled_value?(value), do: String.downcase(value) in ["1", "true", "yes"]
end
