defmodule JidoDelvetown.Automation do
  @moduledoc "Oban-backed automation schedule and runtime status."

  @reactive_worker JidoDelvetown.Workers.ReactiveParticipationWorker
  @friend_sync_worker JidoDelvetown.Workers.FriendSyncWorker

  def running?, do: is_pid(Oban.whereis(Oban))

  def reactive_cron do
    worker_cron(@reactive_worker)
  end

  def friend_sync_cron, do: worker_cron(@friend_sync_worker)

  def crontab do
    :jido_delvetown
    |> Application.fetch_env!(Oban)
    |> Keyword.fetch!(:cron)
    |> Keyword.fetch!(:crontab)
  end

  defp worker_cron(worker) do
    Enum.find_value(crontab(), fn
      {cron, ^worker} -> cron
      {cron, ^worker, _options} -> cron
      _entry -> nil
    end)
  end
end
