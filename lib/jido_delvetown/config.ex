defmodule JidoDelvetown.Config do
  @moduledoc false

  @default_data_dir Path.expand("../../tmp/jido_delvetown", __DIR__)

  def load_env(path \\ ".env") do
    if File.regular?(path) do
      System.put_env(Dotenvy.source!([path, System.get_env()], side_effect: nil))
    end

    :ok
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

  defp enabled_value?(value), do: String.downcase(value) in ["1", "true", "yes"]
end
