defmodule JidoDelvetown.MemberDiscoveryCycle do
  @moduledoc "Finds recent DelveTown members and selects at most one welcome."

  Code.ensure_compiled!(JidoDelvetown.Actions.ApplyDecision)
  Code.ensure_compiled!(JidoDelvetown.Actions.DecideParticipation)
  Code.ensure_compiled!(JidoDelvetown.Actions.RecordCycle)
  Code.ensure_compiled!(JidoDelvetown.ParticipationResponseFlow)

  use Jido.Flow,
    name: "delvetown_member_discovery_cycle",
    schema:
      Zoi.object(%{
        mode: Zoi.enum(["normal", "review"]) |> Zoi.default("normal")
      }),
    output_schema: Zoi.map()

  flow do
    step "collect_context",
      action: JidoDelvetown.Actions.CollectContext,
      params: %{kind: "members", mode: input(:mode)}

    step "select_intent",
      action: JidoDelvetown.Actions.SelectIntent,
      params: %{cycle: result("collect_context")}

    step "respond",
      action: JidoDelvetown.ParticipationResponseFlow,
      params: %{cycle: result("select_intent")}

    output result("respond")
  end
end
