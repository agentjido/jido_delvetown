defmodule JidoDelvetown.WorkersTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias JidoDelvetown.Automation
  alias JidoDelvetown.Config
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Workers.FriendSyncWorker
  alias JidoDelvetown.Workers.MemberDiscoveryWorker
  alias JidoDelvetown.Workers.ProactiveReviewWorker
  alias JidoDelvetown.Workers.ReactiveParticipationWorker

  defmodule FakeCycleRunner do
    def run_reactive, do: run(:reactive)
    def review_proactive, do: run(:proactive_review)
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

  defmodule UnavailableRuntime do
    def agent_server, do: {:error, :agent_not_running}
  end

  setup do
    old_runner = Application.get_env(:jido_delvetown, :cycle_runner)
    old_owner = Application.get_env(:jido_delvetown, :test_owner)
    old_result = Application.get_env(:jido_delvetown, :cycle_result)
    old_syncer = Application.get_env(:jido_delvetown, :friend_syncer)
    old_sync_result = Application.get_env(:jido_delvetown, :friend_sync_result)
    old_review_runtime = Application.get_env(:jido_delvetown, :reactive_review_runtime)

    Application.put_env(:jido_delvetown, :cycle_runner, FakeCycleRunner)
    Application.put_env(:jido_delvetown, :test_owner, self())
    Application.put_env(:jido_delvetown, :cycle_result, {:ok, %{status: "completed"}})
    Application.put_env(:jido_delvetown, :friend_syncer, FakeFriendSyncer)
    Application.put_env(:jido_delvetown, :friend_sync_result, {:ok, %{seen: 2}})
    Application.delete_env(:jido_delvetown, :reactive_review_runtime)
    Repo.delete_all(Oban.Job)

    on_exit(fn ->
      restore_env(:cycle_runner, old_runner)
      restore_env(:test_owner, old_owner)
      restore_env(:cycle_result, old_result)
      restore_env(:friend_syncer, old_syncer)
      restore_env(:friend_sync_result, old_sync_result)
      restore_env(:reactive_review_runtime, old_review_runtime)
      Repo.delete_all(Oban.Job)
    end)

    :ok
  end

  test "reactive jobs run the reactive cycle" do
    assert :ok = ReactiveParticipationWorker.perform(%Oban.Job{})
    assert_receive {:cycle, :reactive}
  end

  test "scheduled proactive jobs run only the proposal review cycle" do
    assert :ok = ProactiveReviewWorker.perform(%Oban.Job{})
    assert_receive {:cycle, :proactive_review}
    refute_receive {:cycle, :proactive}
  end

  test "one incomplete proactive review job blocks an overlapping job" do
    assert {:ok, first} = Oban.insert(ProactiveReviewWorker.new(%{"source" => "cron"}))
    refute first.conflict?

    assert {:ok, duplicate} =
             Oban.insert(ProactiveReviewWorker.new(%{"source" => "cron"}))

    assert duplicate.conflict?
    assert duplicate.id == first.id
    assert Repo.aggregate(proactive_review_jobs_query(), :count) == 1
  end

  test "proactive review retries keep proposal-only behavior" do
    Application.put_env(
      :jido_delvetown,
      :cycle_result,
      {:ok, %{status: "failed", stage: "collect", errors: ["timeout"]}}
    )

    job = %Oban.Job{attempt: 1, max_attempts: 5}

    assert {:error, {:cycle_failed, "collect", ["timeout"]}} =
             ProactiveReviewWorker.perform(job)

    assert {:error, {:cycle_failed, "collect", ["timeout"]}} =
             ProactiveReviewWorker.perform(%{job | attempt: 2})

    assert_receive {:cycle, :proactive_review}
    assert_receive {:cycle, :proactive_review}
    refute_receive {:cycle, :proactive}
  end

  test "a manual reactive review runs through Oban and records completion" do
    writes_enabled? = Config.write_enabled?()
    dry_run_mark_actioned? = Config.dry_run_mark_actioned?()

    assert {:ok, %{status: :queued, disabled?: true, job_id: job_id}} =
             Automation.enqueue_reactive_review()

    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :delvetown)
    assert_receive {:cycle, :reactive}

    assert %{status: :completed, disabled?: false, job_id: ^job_id} =
             Automation.reactive_review_status()

    assert Config.write_enabled?() == writes_enabled?
    assert Config.dry_run_mark_actioned?() == dry_run_mark_actioned?
  end

  test "repeated manual review requests do not create concurrent jobs" do
    assert {:ok, %{status: :queued, job_id: job_id}} = Automation.enqueue_reactive_review()

    assert {:ok, %{status: :skipped, disabled?: true, job_id: ^job_id}} =
             Automation.enqueue_reactive_review()

    assert Repo.aggregate(reactive_jobs_query(), :count) == 1
  end

  test "manual review rejects an unavailable agent runtime without queuing a job" do
    Application.put_env(
      :jido_delvetown,
      :reactive_review_runtime,
      UnavailableRuntime
    )

    assert {:error, :runtime_unavailable} = Automation.enqueue_reactive_review()

    assert %{status: :failed, label: "Runtime unavailable", disabled?: true} =
             Automation.reactive_review_status()

    assert Repo.aggregate(reactive_jobs_query(), :count) == 0
  end

  test "a failed manual review shows its pending Oban retry" do
    Application.put_env(
      :jido_delvetown,
      :cycle_result,
      {:ok, %{status: "failed", stage: "collect", errors: ["timeout"]}}
    )

    assert {:ok, %{status: :queued, job_id: job_id}} = Automation.enqueue_reactive_review()
    assert %{success: 0, failure: 1} = Oban.drain_queue(queue: :delvetown)
    assert_receive {:cycle, :reactive}

    assert %{status: :failed, disabled?: true, job_id: ^job_id} =
             Automation.reactive_review_status()
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
    for worker <- [
          ReactiveParticipationWorker,
          ProactiveReviewWorker,
          MemberDiscoveryWorker,
          FriendSyncWorker
        ] do
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

  defp reactive_jobs_query do
    from(job in Oban.Job,
      where: job.worker == ^inspect(ReactiveParticipationWorker)
    )
  end

  defp proactive_review_jobs_query do
    from(job in Oban.Job,
      where: job.worker == ^inspect(ProactiveReviewWorker)
    )
  end
end
