defmodule JidoDelvetown.Actions.DecideParticipation do
  @moduledoc "Uses Imp to select one bounded participation decision."

  use Jido.Action,
    name: "delvetown_decide_participation",
    schema: Zoi.object(%{cycle: Zoi.map()})

  alias JidoDelvetown.Actions.SelectIntent
  alias JidoDelvetown.CreativeFormats
  alias JidoDelvetown.FriendList
  alias JidoDelvetown.ParticipationImageGeneration
  alias JidoDelvetown.Personality
  alias JidoDelvetown.Settings.Behavior

  @actions ~w(reply like repost post acknowledge follow welcome skip)

  @instructions Personality.decision_prompt()

  @signature Imp.signature(
               %{
                 inputs: [
                   %{name: :intent, type: :string},
                   %{name: :allowed_actions, type: "array[string]"},
                   %{name: :context, type: :string}
                 ],
                 outputs: [
                   %{
                     name: :action,
                     type: :string,
                     constraints: %{enum: @actions}
                   },
                   %{
                     name: :text,
                     type: :string,
                     optional: true,
                     constraints: %{max_length: 300}
                   },
                   %{
                     name: :topic,
                     type: :string,
                     optional: true,
                     constraints: %{max_length: 80}
                   },
                   %{
                     name: :reason,
                     type: :string,
                     constraints: %{min_length: 1, max_length: 240}
                   },
                   %{
                     name: :image_prompt,
                     type: :string,
                     optional: true,
                     constraints: %{min_length: 1, max_length: 4000}
                   },
                   %{
                     name: :image_alt_text,
                     type: :string,
                     optional: true,
                     constraints: %{min_length: 1, max_length: 1000}
                   }
                 ]
               },
               @instructions
             )

  @impl true
  def run(%{cycle: %{status: "failed"} = cycle}, _context), do: {:ok, cycle}

  def run(%{cycle: %{intent: "skip"} = cycle}, _context) do
    decision = %{
      action: "skip",
      text: nil,
      topic: nil,
      reason: cycle.reason || "No eligible work"
    }

    {:ok, Map.put(cycle, :decision, decision)}
  end

  def run(%{cycle: cycle}, context) do
    with {:ok, allowed_actions} <- Behavior.filter_enabled_actions(cycle.allowed_actions) do
      cycle = cycle |> Map.put(:allowed_actions, allowed_actions) |> CreativeFormats.prepare()

      payload = %{
        reason: cycle.reason,
        allowed_actions: cycle.allowed_actions,
        membership: cycle.membership,
        candidate: cycle.candidate,
        recent_posts: Enum.take(cycle.recent_posts, 3),
        friends: FriendList.for_context(),
        budget: cycle.state.budget,
        recent_topics: cycle.state.proactive.recent_topics,
        response_format: cycle.response_format,
        image_generation: image_generation_module().proposal_context(cycle.kind)
      }

      case decision_module().choose(cycle.intent, payload, context) do
        {:ok, decision} ->
          {:ok, Map.put(cycle, :decision, CreativeFormats.finalize(decision, cycle))}

        {:error, reason} ->
          failed_cycle(cycle, reason)
      end
    else
      {:error, reason} -> failed_cycle(cycle, reason)
    end
  end

  def choose(intent, payload, _context) do
    with {:ok, model} <- Behavior.decision_model_input() do
      choose_with_lm(intent, payload, Imp.req_llm(model))
    end
  end

  @doc false
  def choose_with_lm(intent, payload, lm) do
    with {:ok, intent_actions} <- SelectIntent.allowed_actions(intent),
         {:ok, allowed_actions} <- allowed_actions(payload, intent_actions),
         {:ok, context} <- Jason.encode(payload),
         {:ok, timeout} <- Behavior.decision_timeout() do
      timeout
      |> Imp.Deadline.with_deadline(fn ->
        lm
        |> program()
        |> Imp.call(%{
          intent: intent,
          allowed_actions: allowed_actions,
          context: context
        })
      end)
      |> normalize()
    else
      :error -> {:error, :unknown_intent}
      {:error, _reason} -> {:error, :invalid_decision_context}
    end
  end

  @doc false
  def program(lm) do
    Imp.predict(@signature,
      lm: lm,
      adapter: Imp.Adapter.JSON,
      config: [json_retries: 1]
    )
  end

  defp normalize({:ok, prediction}) do
    decision = %{
      action: Imp.get(prediction, :action),
      text: Imp.get(prediction, :text),
      topic: Imp.get(prediction, :topic),
      reason: Imp.get(prediction, :reason)
    }

    {:ok,
     decision
     |> maybe_put(:image_prompt, Imp.get(prediction, :image_prompt))
     |> maybe_put(:image_alt_text, Imp.get(prediction, :image_alt_text))}
  end

  defp normalize({:error, _reason}), do: {:error, :decision_failed}

  defp decision_module do
    Application.get_env(:jido_delvetown, :decision_module, __MODULE__)
  end

  defp image_generation_module do
    Application.get_env(
      :jido_delvetown,
      :participation_image_generation,
      ParticipationImageGeneration
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp allowed_actions(payload, intent_actions) do
    actions =
      Map.get(payload, :allowed_actions) || Map.get(payload, "allowed_actions") || intent_actions

    if actions != [] and is_list(actions) and
         Enum.all?(actions, &(is_binary(&1) and &1 in intent_actions)) do
      {:ok, actions}
    else
      {:error, :invalid_allowed_actions}
    end
  end

  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(_reason), do: "decision_failed"

  defp failed_cycle(cycle, reason) do
    {:ok,
     Map.merge(cycle, %{
       status: "failed",
       stage: "decision",
       errors: cycle.errors ++ [error_text(reason)]
     })}
  end
end
