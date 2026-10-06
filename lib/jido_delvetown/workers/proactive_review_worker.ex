defmodule JidoDelvetown.Workers.ProactiveReviewWorker do
  @moduledoc "Runs one durable, proposal-only proactive participation review."

  use Oban.Worker,
    queue: :delvetown,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker]]

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run_review()

  defp run_review do
    cycle_runner()
    |> apply(:review_proactive, [])
    |> normalize_result()
  end

  defp normalize_result({:ok, %{status: "failed"} = result}) do
    {:error, {:cycle_failed, Map.get(result, :stage), Map.get(result, :errors, [])}}
  end

  defp normalize_result({:ok, _result}), do: :ok
  defp normalize_result({:error, reason}), do: {:error, reason}

  defp cycle_runner,
    do:
      Application.get_env(
        :jido_delvetown,
        :cycle_runner,
        JidoDelvetown.Participation.CycleRunner
      )
end
