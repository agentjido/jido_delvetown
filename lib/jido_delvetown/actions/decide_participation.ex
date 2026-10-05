defmodule JidoDelvetown.Actions.DecideParticipation do
  @moduledoc "Uses Imp to select one bounded participation decision."

  use Jido.Action,
    name: "delvetown_decide_participation",
    schema: Zoi.object(%{cycle: Zoi.map()})

  alias JidoDelvetown.Actions.SelectIntent
  alias JidoDelvetown.Config
  alias JidoDelvetown.Personality

  @actions ~w(reply like repost post skip)

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
    payload = %{
      reason: cycle.reason,
      membership: cycle.membership,
      candidate: cycle.candidate,
      recent_posts: Enum.take(cycle.recent_posts, 3),
      budget: cycle.state.budget,
      recent_topics: cycle.state.proactive.recent_topics
    }

    case decision_module().choose(cycle.intent, payload, context) do
      {:ok, decision} ->
        {:ok, Map.put(cycle, :decision, decision)}

      {:error, reason} ->
        {:ok,
         Map.merge(cycle, %{
           status: "failed",
           stage: "decision",
           errors: cycle.errors ++ [error_text(reason)]
         })}
    end
  end

  def choose(intent, payload, _context) do
    choose_with_lm(intent, payload, Imp.req_llm(Config.decision_model_input()))
  end

  @doc false
  def choose_with_lm(intent, payload, lm) do
    with {:ok, allowed_actions} <- SelectIntent.allowed_actions(intent),
         {:ok, context} <- Jason.encode(payload) do
      Config.decision_timeout()
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
    {:ok,
     %{
       action: Imp.get(prediction, :action),
       text: Imp.get(prediction, :text),
       topic: Imp.get(prediction, :topic),
       reason: Imp.get(prediction, :reason)
     }}
  end

  defp normalize({:error, _reason}), do: {:error, :decision_failed}

  defp decision_module do
    Application.get_env(:jido_delvetown, :decision_module, __MODULE__)
  end

  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(_reason), do: "decision_failed"
end
