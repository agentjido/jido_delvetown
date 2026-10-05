defmodule JidoDelvetown.Database do
  @moduledoc false

  use GenServer

  alias JidoDelvetown.Repo

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    path = Application.app_dir(:jido_delvetown, "priv/repo/migrations")
    _versions = Ecto.Migrator.run(Repo, path, :up, all: true)
    {:ok, %{migration_path: path}}
  end
end
