defmodule JidoDelvetown.Automation do
  @moduledoc "Oban-backed automation schedule and runtime status."

  import Ecto.Query

  alias JidoDelvetown.Repo

  @reactive_worker JidoDelvetown.Workers.ReactiveParticipationWorker
  @proactive_review_worker JidoDelvetown.Workers.ProactiveReviewWorker
  @friend_sync_worker JidoDelvetown.Workers.FriendSyncWorker
  @manual_source "admin"
  @active_states ~w(available scheduled executing retryable suspended)

  def running?, do: is_pid(Oban.whereis(Oban))

  @doc "Queues one manual reactive review without changing protocol-write settings."
  def enqueue_reactive_review, do: enqueue_review(@reactive_worker, :reactive)

  @doc "Queues one manual proposal-only proactive review without changing write settings."
  def enqueue_proactive_review, do: enqueue_review(@proactive_review_worker, :proactive)

  @doc "Returns the current or most recent manual reactive review state."
  def reactive_review_status, do: review_status(@reactive_worker, :reactive)

  @doc "Returns the current or most recent manual proactive review state."
  def proactive_review_status, do: review_status(@proactive_review_worker, :proactive)

  defp enqueue_review(worker, kind) do
    with :ok <- ensure_runtime_available(),
         {:ok, job} <- Oban.insert(worker.new(%{"source" => @manual_source})) do
      if job.conflict? do
        {:ok, feedback(job, kind, :skipped)}
      else
        {:ok, feedback(job, kind)}
      end
    else
      {:error, :runtime_unavailable} = error -> error
      {:error, reason} -> {:error, {:enqueue_failed, reason}}
    end
  rescue
    error -> {:error, {:enqueue_failed, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:enqueue_failed, reason}}
  end

  defp review_status(worker, kind) do
    case ensure_runtime_available() do
      :ok ->
        case active_job(worker) || latest_manual_job(worker) do
          nil -> idle_feedback(kind)
          job -> feedback(job, kind)
        end

      {:error, :runtime_unavailable} ->
        %{
          status: :failed,
          label: "Runtime unavailable",
          detail: "Start the Agent and Oban runtimes before you run a #{kind} review.",
          disabled?: true,
          job_id: nil
        }
    end
  rescue
    error -> failed_feedback("Review status is unavailable: #{Exception.message(error)}")
  catch
    :exit, reason -> failed_feedback("Review status is unavailable: #{inspect(reason)}")
  end

  def reactive_cron do
    worker_cron(@reactive_worker)
  end

  def proactive_review_cron, do: worker_cron(@proactive_review_worker)
  def friend_sync_cron, do: worker_cron(@friend_sync_worker)

  @doc "Returns bounded schedule and latest-job health for proactive reviews."
  def proactive_review_health(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    latest_job =
      repo.one(
        from(job in Oban.Job,
          where: job.worker == ^inspect(@proactive_review_worker),
          order_by: [desc: job.inserted_at, desc: job.id],
          limit: 1
        )
      )

    %{
      cron: proactive_review_cron(),
      queue: "delvetown",
      max_attempts: @proactive_review_worker.__opts__()[:max_attempts],
      last_run: proactive_job_health(latest_job)
    }
  end

  def crontab do
    :jido_delvetown
    |> Application.fetch_env!(Oban)
    |> Keyword.fetch!(:cron)
    |> Keyword.fetch!(:crontab)
  end

  defp ensure_runtime_available do
    with pid when is_pid(pid) <- Oban.whereis(Oban),
         {:ok, agent_server} when is_pid(agent_server) <- runtime().agent_server(),
         true <- Process.alive?(agent_server) do
      :ok
    else
      _unavailable -> {:error, :runtime_unavailable}
    end
  end

  defp active_job(worker) do
    Repo.one(
      from(job in Oban.Job,
        where: job.worker == ^inspect(worker) and job.state in ^@active_states,
        order_by: [desc: job.inserted_at, desc: job.id],
        limit: 1
      )
    )
  end

  defp latest_manual_job(worker) do
    Repo.one(
      from(job in Oban.Job,
        where:
          job.worker == ^inspect(worker) and
            fragment("json_extract(?, '$.source')", job.args) == ^@manual_source,
        order_by: [desc: job.inserted_at, desc: job.id],
        limit: 1
      )
    )
  end

  defp feedback(job, kind, override \\ nil)

  defp feedback(job, kind, :skipped) do
    %{
      status: :skipped,
      label: "Review already queued",
      detail: "A #{kind} review is already queued or running. No duplicate job was created.",
      disabled?: true,
      job_id: job.id
    }
  end

  defp feedback(%{state: state} = job, kind, nil) when state in ["available", "scheduled"] do
    %{
      status: :queued,
      label: "Review queued",
      detail: queued_detail(job, kind),
      disabled?: true,
      job_id: job.id
    }
  end

  defp feedback(%{state: "executing"} = job, kind, nil) do
    %{
      status: :running,
      label: "Review running",
      detail: "The #{kind} worker is collecting and reviewing events.",
      disabled?: true,
      job_id: job.id
    }
  end

  defp feedback(%{state: state} = job, _kind, nil) when state in ["retryable", "suspended"] do
    %{
      status: :failed,
      label: "Review failed",
      detail: "The worker failed. Oban will retry this job, so another review cannot start yet.",
      disabled?: true,
      job_id: job.id
    }
  end

  defp feedback(%{state: "completed"} = job, kind, nil) do
    %{
      status: :completed,
      label: "Review completed",
      detail: completed_detail(kind),
      disabled?: false,
      job_id: job.id
    }
  end

  defp feedback(%{state: state} = job, _kind, nil) when state in ["discarded", "cancelled"] do
    %{
      status: :failed,
      label: "Review failed",
      detail: "The job stopped without a completed review. Check the local logs before retrying.",
      disabled?: false,
      job_id: job.id
    }
  end

  defp feedback(job, kind, nil) do
    failed_feedback("The #{kind} review has an unknown Oban state: #{job.state}", job.id)
  end

  defp queued_detail(%{args: %{"source" => @manual_source}}, :reactive),
    do: "The manual review will run through the normal SQLite scan lease."

  defp queued_detail(%{args: %{"source" => @manual_source}}, :proactive),
    do: "The manual review will use the timeline scan lease and save proposals only."

  defp queued_detail(_job, kind),
    do: "A scheduled #{kind} review is already queued. Manual review is disabled until it ends."

  defp completed_detail(:reactive),
    do: "The dashboard now includes events and simulated replies from this review."

  defp completed_detail(:proactive),
    do: "The dashboard now includes proposals from this timeline review."

  defp idle_feedback(:reactive) do
    %{
      status: :idle,
      label: "Ready for review",
      detail: "Queue one reactive review. Current write and dry-run settings stay unchanged.",
      disabled?: false,
      job_id: nil
    }
  end

  defp idle_feedback(:proactive) do
    %{
      status: :idle,
      label: "Ready for proactive review",
      detail: "Queue one timeline review. It can save proposals but cannot publish them.",
      disabled?: false,
      job_id: nil
    }
  end

  defp failed_feedback(detail, job_id \\ nil) do
    %{
      status: :failed,
      label: "Review status failed",
      detail: detail,
      disabled?: true,
      job_id: job_id
    }
  end

  defp runtime,
    do: Application.get_env(:jido_delvetown, :reactive_review_runtime, JidoDelvetown)

  defp proactive_job_health(nil) do
    %{
      health: "idle",
      state: nil,
      job_id: nil,
      attempt: 0,
      max_attempts: @proactive_review_worker.__opts__()[:max_attempts],
      inserted_at: nil,
      attempted_at: nil,
      completed_at: nil,
      error_count: 0
    }
  end

  defp proactive_job_health(job) do
    %{
      health: job_health(job.state),
      state: job.state,
      job_id: job.id,
      attempt: job.attempt,
      max_attempts: job.max_attempts,
      inserted_at: iso8601(job.inserted_at),
      attempted_at: iso8601(job.attempted_at),
      completed_at: iso8601(job.completed_at),
      error_count: length(job.errors || [])
    }
  end

  defp job_health("completed"), do: "healthy"
  defp job_health(state) when state in ["available", "scheduled", "executing"], do: "active"
  defp job_health(state) when state in ["retryable", "suspended"], do: "retrying"
  defp job_health(state) when state in ["discarded", "cancelled"], do: "failed"
  defp job_health(_state), do: "unknown"

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp worker_cron(worker) do
    Enum.find_value(crontab(), fn
      {cron, ^worker} -> cron
      {cron, ^worker, _options} -> cron
      _entry -> nil
    end)
  end
end
