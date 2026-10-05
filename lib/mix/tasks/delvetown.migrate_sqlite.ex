defmodule Mix.Tasks.Delvetown.MigrateSqlite do
  @moduledoc "Imports and verifies the former DETS and file persistence data."

  use Mix.Task

  @shortdoc "Import former local persistence into SQLite"
  @requirements ["app.config"]

  @impl true
  def run(args) do
    Mix.Task.run("loadpaths")
    :ok = JidoDelvetown.Config.load_env()
    {:ok, _apps} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, repo} = JidoDelvetown.Repo.start_link()
    Process.unlink(repo)
    {:ok, database} = JidoDelvetown.Database.start_link()
    Process.unlink(database)

    try do
      if "--preview" in args do
        print_result(JidoDelvetown.LegacyImporter.preview())
      else
        print_result(JidoDelvetown.LegacyImporter.run())
        print_result(JidoDelvetown.LegacyImporter.verify())
      end
    after
      GenServer.stop(database)
      GenServer.stop(repo)
    end
  end

  defp print_result({:ok, result}), do: Mix.shell().info(inspect(result, pretty: true))

  defp print_result({:error, reason}) do
    Mix.raise("Legacy import failed: #{inspect(reason)}")
  end
end
