defmodule JidoDelvetown.ParticipationCycle do
  @moduledoc "The finite reactive and proactive Delvetown participation cycle."

  use Jido.Flow,
    name: "delvetown_participation_cycle",
    schema:
      Zoi.object(%{
        mode: Zoi.enum(["normal", "review"]) |> Zoi.default("normal")
      }),
    output_schema: Zoi.map()

  flow do
    step "collect_context",
      action: JidoDelvetown.Actions.CollectContext,
      params: %{mode: input(:mode)}

    step "select_intent",
      action: JidoDelvetown.Actions.SelectIntent,
      params: %{cycle: result("collect_context")}

    step "decide",
      action: JidoDelvetown.Actions.DecideParticipation,
      params: %{cycle: result("select_intent")}

    step "apply_decision",
      action: JidoDelvetown.Actions.ApplyDecision,
      params: %{cycle: result("decide")}

    step "record_state",
      action: JidoDelvetown.Actions.RecordCycle,
      params: %{cycle: result("apply_decision")}

    output result("record_state")
  end
end
