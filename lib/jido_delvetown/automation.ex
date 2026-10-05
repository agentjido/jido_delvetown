defmodule JidoDelvetown.Automation do
  @moduledoc "Oban-backed automation schedule and runtime status."

  @reactive_worker JidoDelvetown.Workers.ReactiveParticipationWorker

  def running?, do: is_pid(Oban.whereis(Oban))

  def reactive_cron do
    Enum.find_value(crontab(), fn
      {cron, @reactive_worker} -> cron
      {cron, @reactive_worker, _options} -> cron
      _entry -> nil
    end)
  end

  def crontab do
    :jido_delvetown
    |> Application.fetch_env!(Oban)
    |> Keyword.fetch!(:cron)
    |> Keyword.fetch!(:crontab)
  end
end
