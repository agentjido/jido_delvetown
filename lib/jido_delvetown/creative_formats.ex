defmodule JidoDelvetown.CreativeFormats do
  @moduledoc "Selects and validates bounded AgentJido response formats."

  @formats %{
    "protocol_field_note" =>
      "Use one observed protocol detail, explain why it matters, and name one boundary or next check.",
    "state_machine_sketch" =>
      "Describe the key states or transition in compact prose. Do not invent implementation facts.",
    "failure_mode_question" =>
      "Name one concrete failure mode, then ask one focused question only when it moves the discussion forward.",
    "short_build_log" =>
      "Use a short build-log shape: what changed, what was learned, and the next small test."
  }

  @intent_formats %{
    "answer_direct_request" => [
      "state_machine_sketch",
      "protocol_field_note",
      "failure_mode_question"
    ],
    "join_useful_discussion" => [
      "failure_mode_question",
      "state_machine_sketch",
      "protocol_field_note"
    ],
    "publish_daily_note" => [
      "short_build_log",
      "protocol_field_note",
      "failure_mode_question"
    ],
    "respond_to_new_follow" => ["protocol_field_note", "short_build_log"],
    "welcome_new_member" => ["protocol_field_note", "short_build_log"]
  }

  @generic_openings ["great point", "interesting question", "i completely agree"]

  def prepare(%{intent: intent, state: state} = cycle) do
    recent = get_in(state, [:voice, :recent_formats]) || []
    allowed = Map.get(@intent_formats, intent, ["protocol_field_note"])
    selected = Enum.find(allowed, &(&1 not in Enum.take(recent, 2))) || List.last(allowed)

    Map.put(cycle, :response_format, %{
      id: selected,
      guidance: Map.fetch!(@formats, selected),
      safety:
        "Format changes presentation only. Accuracy, privacy, opt-out, representation, tone, and length rules still apply."
    })
  end

  def finalize(decision, cycle) when is_map(decision) do
    decision = Map.put(decision, :format, get_in(cycle, [:response_format, :id]))

    case validate(decision, cycle.state) do
      :ok -> decision
      {:error, reason} -> fallback(reason, decision)
    end
  end

  def validate(%{action: action}, _state)
      when action in ["skip", "acknowledge", "follow", "like", "repost"],
      do: :ok

  def validate(%{text: text, topic: topic}, state) when is_binary(text) do
    opening = opening(text)
    recent_openings = get_in(state, [:voice, :recent_openings]) || []
    recent_topics = get_in(state, [:voice, :recent_topics]) || []

    cond do
      generic_opening?(text) ->
        {:error, :generic_opening}

      Enum.count(recent_openings, &(&1 == opening)) >= 2 ->
        {:error, :repeated_opening}

      is_binary(topic) and topic != "" and Enum.count(recent_topics, &(&1 == topic)) >= 2 ->
        {:error, :repeated_topic}

      true ->
        :ok
    end
  end

  def validate(_decision, _state), do: {:error, :missing_response_text}

  def opening(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.split()
    |> Enum.take(4)
    |> Enum.join(" ")
  end

  defp generic_opening?(text) do
    normalized = String.downcase(String.trim(text))
    Enum.any?(@generic_openings, &String.starts_with?(normalized, &1))
  end

  defp fallback(reason, decision) do
    %{
      action: "skip",
      text: nil,
      topic: Map.get(decision, :topic),
      reason: "creative_format_validation_failed:#{reason}",
      format: "validation_fallback"
    }
  end
end
