defmodule JidoDelvetown.Database do
  @moduledoc false

  use GenServer

  alias JidoDelvetown.{InteractionEvents, Repo}
  alias JidoDelvetown.Persistence.Legacy.Startup, as: LegacyStartup
  alias JidoDelvetown.Settings.Bootstrap, as: SettingsBootstrap
  alias JidoDelvetown.Settings.SecretStore

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    path = Application.app_dir(:jido_delvetown, "priv/repo/migrations")
    _versions = Ecto.Migrator.run(Repo, path, :up, all: true)

    with {:ok, _key} <- SecretStore.ensure_key(),
         {:ok, _settings} <- SettingsBootstrap.run(),
         :ok <- LegacyStartup.run(),
         {:ok, _count} <- InteractionEvents.recover_stale_claims(stale_after_ms: 0) do
      {:ok, %{migration_path: path}}
    else
      {:error, reason} -> {:stop, {:database_initialization_failed, reason}}
    end
  end
end
