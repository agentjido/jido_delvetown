defmodule JidoDelvetown.Automation do
  @moduledoc "Oban-backed automation schedule and runtime status."

  import Ecto.Query

  alias JidoDelvetown.Repo

  @reactive_worker JidoDelvetown.Workers.ReactiveParticipationWorker
  @friend_sync_worker JidoDelvetown.Workers.FriendSyncWorker
  @manual_source "admin"
  @active_states ~w(available scheduled executing retryable suspended)

  def running?, do: is_pid(Oban.whereis(Oban))

  @doc "Queues one manual reactive review without changing protocol-write settings."
  def enqueue_reactive_review do
    with :ok <- ensure_runtime_available(),
         {:ok, job} <- Oban.insert(@reactive_worker.new(%{"source" => @manual_source})) do
      if job.conflict? do
        {:ok, feedback(job, :skipped)}
      else
        {:ok, feedback(job)}
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

  @doc "Returns the current or most recent manual reactive review state."
  def reactive_review_status do
    case ensure_runtime_available() do
      :ok ->
        case active_reactive_job() || latest_manual_reactive_job() do
          nil -> idle_feedback()
          job -> feedback(job)
        end

      {:error, :runtime_unavailable} ->
        %{
          status: :failed,
          label: "Runtime unavailable",
          detail: "Start the Agent and Oban runtimes before you run a reactive review.",
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

  def friend_sync_cron, do: worker_cron(@friend_sync_worker)

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

  defp active_reactive_job do
    Repo.one(
      from(job in Oban.Job,
        where: job.worker == ^inspect(@reactive_worker) and job.state in ^@active_states,
        order_by: [desc: job.inserted_at, desc: job.id],
        limit: 1
      )
    )
  end

  defp latest_manual_reactive_job do
    Repo.one(
      from(job in Oban.Job,
        where:
          job.worker == ^inspect(@reactive_worker) and
            fragment("json_extract(?, '$.source')", job.args) == ^@manual_source,
        order_by: [desc: job.inserted_at, desc: job.id],
        limit: 1
      )
    )
  end

  defp feedback(job, override \\ nil)

  defp feedback(job, :skipped) do
    %{
      status: :skipped,
      label: "Review already queued",
      detail: "A reactive review is already queued or running. No duplicate job was created.",
      disabled?: true,
      job_id: job.id
    }
  end

  defp feedback(%{state: state} = job, nil) when state in ["available", "scheduled"] do
    %{
      status: :queued,
      label: "Review queued",
      detail: queued_detail(job),
      disabled?: true,
      job_id: job.id
    }
  end

  defp feedback(%{state: "executing"} = job, nil) do
    %{
      status: :running,
      label: "Review running",
      detail: "The reactive worker is collecting and reviewing events.",
      disabled?: true,
      job_id: job.id
    }
  end

  defp feedback(%{state: state} = job, nil) when state in ["retryable", "suspended"] do
    %{
      status: :failed,
      label: "Review failed",
      detail: "The worker failed. Oban will retry this job, so another review cannot start yet.",
      disabled?: true,
      job_id: job.id
    }
  end

  defp feedback(%{state: "completed"} = job, nil) do
    %{
      status: :completed,
      label: "Review completed",
      detail: "The dashboard now includes events and simulated replies from this review.",
      disabled?: false,
      job_id: job.id
    }
  end

  defp feedback(%{state: state} = job, nil) when state in ["discarded", "cancelled"] do
    %{
      status: :failed,
      label: "Review failed",
      detail: "The job stopped without a completed review. Check the local logs before retrying.",
      disabled?: false,
      job_id: job.id
    }
  end

  defp feedback(job, nil) do
    failed_feedback("The reactive review has an unknown Oban state: #{job.state}", job.id)
  end

  defp queued_detail(%{args: %{"source" => @manual_source}}),
    do: "The manual review will run through the normal SQLite scan lease."

  defp queued_detail(_job),
    do: "A scheduled reactive review is already queued. Manual review is disabled until it ends."

  defp idle_feedback do
    %{
      status: :idle,
      label: "Ready for review",
      detail: "Queue one reactive review. Current write and dry-run settings stay unchanged.",
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

  defp worker_cron(worker) do
    Enum.find_value(crontab(), fn
      {cron, ^worker} -> cron
      {cron, ^worker, _options} -> cron
      _entry -> nil
    end)
  end
end
