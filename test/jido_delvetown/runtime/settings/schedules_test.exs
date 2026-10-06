defmodule JidoDelvetown.Settings.SchedulesTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{Automation, Settings}
  alias JidoDelvetown.Settings.Schedules
  alias JidoDelvetown.Test.RuntimeSettings

  alias JidoDelvetown.Workers.{
    FriendSyncWorker,
    MemberDiscoveryWorker,
    ProactiveReviewWorker,
    ReactiveParticipationWorker
  }

  setup do
    restore_settings =
      RuntimeSettings.preserve!(
        reactive_review_cron: "*/15 * * * *",
        proactive_review_cron: "5,35 * * * *",
        member_discovery_cron: "7 * * * *",
        friend_sync_cron: "17 * * * *"
      )

    on_exit(restore_settings)
    :ok
  end

  test "builds the complete Oban crontab from one SQLite snapshot" do
    assert {:ok, schedules} = Schedules.current()
    assert schedules.reactive_review_cron == "*/15 * * * *"
    assert schedules.proactive_review_cron == "5,35 * * * *"
    assert schedules.member_discovery_cron == "7 * * * *"
    assert schedules.friend_sync_cron == "17 * * * *"

    assert {:ok, crontab} = Schedules.crontab()

    assert crontab == [
             {"*/15 * * * *", ReactiveParticipationWorker},
             {"5,35 * * * *", ProactiveReviewWorker},
             {"7 * * * *", MemberDiscoveryWorker},
             {"17 * * * *", FriendSyncWorker}
           ]
  end

  test "an active schedule update replaces the Cron child and keeps all workers" do
    oban_pid = Oban.whereis(Oban)
    automation_pid = Process.whereis(JidoDelvetown.AutomationRuntime)
    old_pid = Oban.Registry.whereis(Oban, {:plugin, Oban.Cron})
    assert is_pid(oban_pid)
    assert is_pid(automation_pid)
    assert is_pid(old_pid)

    assert {:ok, updated} =
             Settings.update(%{reactive_review_cron: "1,16,31,46 * * * *"}, source: "test")

    assert updated.values.reactive_review_cron == "1,16,31,46 * * * *"

    new_pid = Oban.Registry.whereis(Oban, {:plugin, Oban.Cron})
    assert Oban.whereis(Oban) == oban_pid
    assert Process.whereis(JidoDelvetown.AutomationRuntime) == automation_pid
    assert is_pid(new_pid)
    refute new_pid == old_pid

    assert Automation.crontab() == [
             {"1,16,31,46 * * * *", ReactiveParticipationWorker},
             {"5,35 * * * *", ProactiveReviewWorker},
             {"7 * * * *", MemberDiscoveryWorker},
             {"17 * * * *", FriendSyncWorker}
           ]

    assert runtime_crontab(new_pid) == Automation.crontab()
  end

  defp runtime_crontab(pid) do
    pid
    |> :sys.get_state()
    |> Map.fetch!(:crontab)
    |> Enum.map(fn {expression, _parsed, worker, _opts, _timezone} -> {expression, worker} end)
  end
end
