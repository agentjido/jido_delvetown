defmodule JidoDelvetown.EngagementRanker do
  @moduledoc "Scores engagement opportunities with explicit, stable policy factors."

  alias JidoDelvetown.Settings.Limits

  @topic_terms ~w(agent beam failure jido otp process protocol recovery supervisor tool)

  def best(candidates, opportunity, state, opts \\ []) when is_list(candidates) do
    candidates
    |> Enum.map(&attach_score(&1, opportunity, state, opts))
    |> Enum.sort_by(fn candidate ->
      rank = candidate.engagement_rank
      {-rank.score, stable_id(candidate)}
    end)
    |> List.first()
  end

  def score(candidate, opportunity, state, opts \\ []) do
    limits = Keyword.get_lazy(opts, :limits, &limits/0)

    factors = %{
      priority: priority(candidate, opportunity),
      recency: recency(candidate, Keyword.get(opts, :now, DateTime.utc_now())),
      relevance: relevance(candidate),
      prior_contact: prior_contact(candidate),
      conversation_load: conversation_load(candidate),
      budget: budget(opportunity, state, limits)
    }

    score = factors |> Map.values() |> Enum.sum()

    %{
      score: score,
      factors: factors,
      reason: reason(opportunity, score, factors)
    }
  end

  defp attach_score(candidate, opportunity, state, opts) do
    Map.put(candidate, :engagement_rank, score(candidate, opportunity, state, opts))
  end

  defp priority(%{reason: "reply"}, :direct), do: 100
  defp priority(%{reason: "mention"}, :direct), do: 95
  defp priority(_candidate, :follow), do: 65
  defp priority(_candidate, :new_member), do: 55
  defp priority(_candidate, :useful_discussion), do: 40
  defp priority(_candidate, :original_post), do: 20
  defp priority(_candidate, _opportunity), do: 0

  defp recency(%{indexed_at: indexed_at}, now) when is_binary(indexed_at) do
    case DateTime.from_iso8601(indexed_at) do
      {:ok, time, _offset} -> max(20 - max(DateTime.diff(now, time, :hour), 0), 0)
      _invalid -> 0
    end
  end

  defp recency(_candidate, _now), do: 0

  defp relevance(candidate) do
    text =
      case Map.get(candidate, :text) do
        value when is_binary(value) -> String.downcase(value)
        _value -> ""
      end

    matches = Enum.count(@topic_terms, &String.contains?(text, &1))

    cond do
      matches >= 2 -> 15
      matches == 1 -> 10
      String.trim(text) != "" -> 4
      true -> 0
    end
  end

  defp prior_contact(candidate) do
    case get_in(candidate, [:memory, :actor, :contact_count]) do
      nil -> 8
      0 -> 8
      1 -> 2
      count when is_integer(count) -> -min(count * 3, 18)
      _count -> 0
    end
  end

  defp conversation_load(candidate) do
    case get_in(candidate, [:memory, :conversation, :turn_count]) do
      nil -> 5
      0 -> 5
      count when count <= 2 -> 0
      count when is_integer(count) -> -min(count * 2, 20)
      _count -> 0
    end
  end

  defp budget(opportunity, state, limits) when opportunity in [:direct, :useful_discussion] do
    remaining = limits.daily_reply_limit - state.budget.replies
    remaining |> max(0) |> min(10)
  end

  defp budget(:new_member, state, limits) do
    remaining = limits.daily_welcome_limit - Map.get(state.budget, :welcomes, 0)
    remaining |> max(0) |> min(10)
  end

  defp budget(:original_post, state, limits),
    do: max(limits.daily_post_limit - state.budget.posts, 0) |> min(10)

  defp budget(:follow, state, limits),
    do: max(limits.daily_follow_limit - Map.get(state.budget, :follows, 0), 0) |> min(10)

  defp budget(_opportunity, _state, _limits), do: 0

  defp limits do
    case Limits.current() do
      {:ok, limits} ->
        limits

      {:error, _reason} ->
        %{
          daily_reply_limit: 0,
          daily_welcome_limit: 0,
          daily_post_limit: 0,
          daily_follow_limit: 0
        }
    end
  end

  defp reason(opportunity, score, factors) do
    "#{opportunity} scored #{score}: priority #{factors.priority}, recency #{factors.recency}, " <>
      "relevance #{factors.relevance}, prior contact #{factors.prior_contact}, " <>
      "conversation load #{factors.conversation_load}, budget #{factors.budget}"
  end

  defp stable_id(candidate) do
    Map.get(candidate, :event_key) || Map.get(candidate, :id) || ""
  end
end
