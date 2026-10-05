defmodule JidoDelvetown.Actions.EnsureSchedule do
  @moduledoc false

  use Jido.Action,
    name: "delvetown_ensure_schedule",
    schema: Zoi.object(%{})

  alias Jido.Plugin.Scheduler
  alias JidoDelvetown.Agent

  @impl true
  def run(_input, %{agent_state: state}) do
    reactive =
      Scheduler.cron(
        Agent.schedule_job_id(),
        Agent.schedule_cron(),
        Agent.schedule_signal(),
        generation: Agent.schedule_generation()
      )

    members =
      Scheduler.cron(
        Agent.member_schedule_job_id(),
        Agent.member_schedule_cron(),
        Agent.member_schedule_signal(),
        generation: Agent.member_schedule_generation()
      )

    {:ok, state, [reactive, members]}
  end
end
