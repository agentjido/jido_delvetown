defmodule JidoDelvetown.ConversationPolicy do
  @moduledoc "Applies bounded follow-up rules to known conversations."

  alias JidoDelvetown.Settings.Limits

  @low_value ["ok", "okay", "thanks", "thank you", "got it", "understood", "noted"]

  def evaluate(candidate, opts \\ [])

  def evaluate(nil, _opts), do: :new

  def evaluate(candidate, opts) when is_map(candidate) do
    case get_in(candidate, [:memory, :conversation]) do
      nil -> :new
      conversation -> evaluate_known(candidate, conversation, opts)
    end
  end

  def useful_turn?(text) when is_binary(text) do
    normalized = text |> String.downcase() |> String.trim() |> String.trim(".!?")
    words = String.split(normalized)

    String.contains?(text, "?") or
      (length(words) >= 6 and normalized not in @low_value)
  end

  def useful_turn?(_text), do: false

  defp evaluate_known(candidate, conversation, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    case Keyword.get_lazy(opts, :policy, &Limits.conversation_policy/0) do
      {:ok, policy} -> evaluate_with_policy(candidate, conversation, now, policy)
      {:error, _reason} -> {:skip, "conversation_settings_unavailable"}
      policy when is_map(policy) -> evaluate_with_policy(candidate, conversation, now, policy)
    end
  end

  defp evaluate_with_policy(candidate, conversation, now, policy) do
    cond do
      conversation.status != "active" ->
        {:skip, "conversation_closed"}

      conversation.last_record_uri == candidate.uri ->
        {:skip, "duplicate_conversation_turn"}

      conversation.turn_count >= policy.turn_limit ->
        {:skip, "conversation_turn_limit"}

      old_conversation?(conversation.last_action_at, now, policy.max_age_hours) ->
        {:skip, "conversation_too_old"}

      Map.get(conversation, :unanswered_follow_ups, 0) >=
          policy.non_response_limit ->
        {:skip, "conversation_non_response_limit"}

      not useful_turn?(candidate.text) ->
        {:skip, "conversation_no_new_value"}

      true ->
        :continue
    end
  end

  defp old_conversation?(value, now, max_age_hours) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, last_action_at, _offset} ->
        DateTime.diff(now, last_action_at, :hour) > max_age_hours

      _invalid ->
        true
    end
  end

  defp old_conversation?(_value, _now, _max_age_hours), do: true
end
