defmodule JidoDelvetown.Workers.FriendSyncWorker do
  @moduledoc "Syncs the remote follow collection into durable local friend memory."

  use Oban.Worker,
    queue: :delvetown,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker]]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case syncer().sync() do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp syncer,
    do: Application.get_env(:jido_delvetown, :friend_syncer, JidoDelvetown.FriendSync)
end
