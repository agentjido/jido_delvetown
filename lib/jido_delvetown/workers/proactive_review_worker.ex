defmodule JidoDelvetown.Workers.ProactiveReviewWorker do
  @moduledoc "Runs one durable proactive review or operator-requested simulation."

  alias JidoDelvetown.Settings.Behavior

  use Oban.Worker,
    queue: :delvetown,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source" => "admin"}}), do: run_simulation()
  def perform(%Oban.Job{}), do: run_review()

  defp run_simulation do
    case Behavior.action_disposition("normal") do
      {:ok, :simulate} -> run_cycle(:run_proactive)
      {:ok, disposition} -> {:discard, {:simulation_not_enabled, disposition}}
      {:error, reason} -> {:discard, {:simulation_settings_unavailable, reason}}
    end
  end

  defp run_review, do: run_cycle(:review_proactive)

  defp run_cycle(operation) do
    cycle_runner()
    |> apply(operation, [])
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
