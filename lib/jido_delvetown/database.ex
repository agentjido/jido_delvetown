defmodule JidoDelvetown.Database do
  @moduledoc false

  use GenServer

  alias JidoDelvetown.{Config, LegacyImporter, Repo}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    path = Application.app_dir(:jido_delvetown, "priv/repo/migrations")
    _versions = Ecto.Migrator.run(Repo, path, :up, all: true)

    case import_legacy_state() do
      :ok -> {:ok, %{migration_path: path}}
      {:error, reason} -> {:stop, {:legacy_import_failed, reason}}
    end
  end

  defp import_legacy_state do
    if Config.legacy_import_enabled?() do
      case LegacyImporter.run() do
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
