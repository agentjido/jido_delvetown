defmodule JidoDelvetown.Repo do
  @moduledoc "The SQLite repository for all local durable AgentJido data."

  use Ecto.Repo,
    otp_app: :jido_delvetown,
    adapter: Ecto.Adapters.SQLite3

  @impl true
  def init(_type, config) do
    path = JidoDelvetown.Config.database_path()
    :ok = path |> Path.dirname() |> File.mkdir_p()

    {:ok,
     Keyword.merge(
       [
         database: path,
         pool_size: 1,
         busy_timeout: 5_000,
         journal_mode: :wal,
         foreign_keys: :on
       ],
       config
     )}
  end
end
