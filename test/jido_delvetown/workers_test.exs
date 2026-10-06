defmodule JidoDelvetown.WorkersTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Workers.FriendSyncWorker
  alias JidoDelvetown.Workers.MemberDiscoveryWorker
  alias JidoDelvetown.Workers.ReactiveParticipationWorker

  defmodule FakeCycleRunner do
    def run_reactive, do: run(:reactive)
    def run_member_discovery, do: run(:member_discovery)

    defp run(cycle) do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), {:cycle, cycle})
      Application.fetch_env!(:jido_delvetown, :cycle_result)
    end
  end

  defmodule FakeFriendSyncer do
    def sync do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), :friend_sync)
      Application.fetch_env!(:jido_delvetown, :friend_sync_result)
    end
  end

  setup do
    old_runner = Application.get_env(:jido_delvetown, :cycle_runner)
    old_owner = Application.get_env(:jido_delvetown, :test_owner)
    old_result = Application.get_env(:jido_delvetown, :cycle_result)
    old_syncer = Application.get_env(:jido_delvetown, :friend_syncer)
    old_sync_result = Application.get_env(:jido_delvetown, :friend_sync_result)

    Application.put_env(:jido_delvetown, :cycle_runner, FakeCycleRunner)
    Application.put_env(:jido_delvetown, :test_owner, self())
    Application.put_env(:jido_delvetown, :cycle_result, {:ok, %{status: "completed"}})
    Application.put_env(:jido_delvetown, :friend_syncer, FakeFriendSyncer)
    Application.put_env(:jido_delvetown, :friend_sync_result, {:ok, %{seen: 2}})

    on_exit(fn ->
      restore_env(:cycle_runner, old_runner)
      restore_env(:test_owner, old_owner)
      restore_env(:cycle_result, old_result)
      restore_env(:friend_syncer, old_syncer)
      restore_env(:friend_sync_result, old_sync_result)
    end)

    :ok
  end

  test "reactive jobs run the reactive cycle" do
    assert :ok = ReactiveParticipationWorker.perform(%Oban.Job{})
    assert_receive {:cycle, :reactive}
  end

  test "member jobs run the member discovery cycle" do
    assert :ok = MemberDiscoveryWorker.perform(%Oban.Job{})
    assert_receive {:cycle, :member_discovery}
  end

  test "friend sync jobs save the remote friend list" do
    assert :ok = FriendSyncWorker.perform(%Oban.Job{})
    assert_receive :friend_sync
  end

  test "failed cycles return an error for Oban retry" do
    Application.put_env(
      :jido_delvetown,
      :cycle_result,
      {:ok, %{status: "failed", stage: "collect", errors: ["timeout"]}}
    )

    assert {:error, {:cycle_failed, "collect", ["timeout"]}} =
             ReactiveParticipationWorker.perform(%Oban.Job{})
  end

  test "workers use one durable queue and one incomplete job per cycle" do
    for worker <- [ReactiveParticipationWorker, MemberDiscoveryWorker, FriendSyncWorker] do
      options = worker.__opts__()

      assert options[:queue] == :delvetown
      assert options[:max_attempts] == 5
      assert options[:unique] == [period: :infinity, states: :incomplete, fields: [:worker]]
    end
  end

  test "the Oban jobs table is in the application SQLite database" do
    assert {:ok, %{rows: [["oban_jobs"]]}} =
             Ecto.Adapters.SQL.query(
               Repo,
               "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'oban_jobs'",
               []
             )
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_delvetown, key)
  defp restore_env(key, value), do: Application.put_env(:jido_delvetown, key, value)
end
