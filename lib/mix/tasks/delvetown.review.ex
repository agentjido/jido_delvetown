defmodule Mix.Tasks.Delvetown.Review do
  @shortdoc "Runs safe Delvetown review cycles with protocol writes disabled"

  @moduledoc """
  Runs one or more Delvetown Agent cycles in review mode.

      mix delvetown.review
      mix delvetown.review --count 5
      mix delvetown.review --flow proactive --count 5

  The task stops unless both Delvetown write settings are false. It also checks
  that each cycle made zero effects and that the local effect counts did not
  change.
  """

  use Mix.Task

  alias JidoDelvetown.{Config, EffectStore}

  @requirements ["app.start"]
  @switches [count: :integer, flow: :string, help: :boolean]
  @aliases [n: :count, h: :help]
  @maximum_count 20

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} =
      OptionParser.parse(args, strict: @switches, aliases: @aliases)

    cond do
      options[:help] ->
        Mix.shell().info(@moduledoc)

      positional != [] or invalid != [] ->
        Mix.raise("Use: mix delvetown.review [--flow reactive|proactive] [--count N]")

      true ->
        run_reviews(Keyword.get(options, :flow, "proactive"), Keyword.get(options, :count, 1))
    end
  end

  defp run_reviews(flow, count)
       when flow in ["reactive", "proactive"] and is_integer(count) and
              count in 1..@maximum_count do
    ensure_safe!()
    before_counts = EffectStore.counts()

    results =
      for number <- 1..count do
        result = run_review!(flow, number, count)
        print_result(flow, number, count, result)
        result
      end

    ensure_safe!()
    after_counts = EffectStore.counts()

    if before_counts != after_counts do
      Mix.raise(
        "Local effect counts changed: #{inspect(before_counts)} -> #{inspect(after_counts)}"
      )
    end

    Mix.shell().info(
      "Completed #{length(results)} #{flow} review cycle(s). Protocol effects: 0. " <>
        "Effect counts: #{inspect(after_counts)}"
    )
  end

  defp run_reviews(flow, _count) when flow not in ["reactive", "proactive"] do
    Mix.raise("--flow must be reactive or proactive")
  end

  defp run_reviews(_flow, _count) do
    Mix.raise("--count must be an integer from 1 through #{@maximum_count}")
  end

  defp run_review!(flow, number, count) do
    case review(flow) do
      {:ok, %{effects: 0, errors: []} = result} ->
        result

      {:ok, result} ->
        Mix.raise("Review #{number}/#{count} was not clean: #{inspect(result)}")

      {:error, reason} ->
        Mix.raise("Review #{number}/#{count} failed: #{inspect(reason)}")
    end
  end

  defp review("reactive"), do: JidoDelvetown.review_reactive()
  defp review("proactive"), do: JidoDelvetown.review_proactive()

  defp print_result(flow, number, count, result) do
    output =
      result
      |> Map.take([:kind, :status, :intent, :action, :proposal, :reads, :effects, :errors])
      |> Jason.encode!(pretty: true)

    Mix.shell().info("#{String.capitalize(flow)} review #{number}/#{count}:\n#{output}")
  end

  defp ensure_safe! do
    if Config.write_enabled?() do
      Mix.raise("Set DELVETOWN_WRITE_ENABLED=false before you run a review")
    end

    if Config.mark_notifications_seen?() do
      Mix.raise("Set DELVETOWN_MARK_NOTIFICATIONS_SEEN=false before you run a review")
    end
  end
end
