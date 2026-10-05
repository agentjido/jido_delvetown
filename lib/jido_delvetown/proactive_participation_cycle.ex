defmodule JidoDelvetown.ProactiveParticipationCycle do
  @moduledoc "Finds useful Delvetown threads and proposes participation."

  use Jido.Flow,
    name: "delvetown_proactive_participation_cycle",
    schema:
      Zoi.object(%{
        mode: Zoi.enum(["normal", "review"]) |> Zoi.default("normal")
      }),
    output_schema: Zoi.map()

  flow do
    step "collect_context",
      action: JidoDelvetown.Actions.CollectContext,
      params: %{kind: "proactive", mode: input(:mode)}

    step "select_intent",
      action: JidoDelvetown.Actions.SelectIntent,
      params: %{cycle: result("collect_context")}

    step "respond",
      action: JidoDelvetown.ParticipationResponseFlow,
      params: %{cycle: result("select_intent")}

    output result("respond")
  end
end
