defmodule JidoDelvetown.Workers.ReactiveParticipationWorker do
  @moduledoc "Runs one durable reactive participation cycle."

  use Oban.Worker,
    queue: :delvetown,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, fields: [:worker]]

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run_cycle(:run_reactive)

  defp run_cycle(function) do
    cycle_runner()
    |> apply(function, [])
    |> normalize_result()
  end

  defp normalize_result({:ok, %{status: "failed"} = result}) do
    {:error, {:cycle_failed, Map.get(result, :stage), Map.get(result, :errors, [])}}
  end

  defp normalize_result({:ok, _result}), do: :ok
  defp normalize_result({:error, reason}), do: {:error, reason}

  defp cycle_runner,
    do: Application.get_env(:jido_delvetown, :cycle_runner, JidoDelvetown)
end
