defmodule JidoDelvetown.ParticipationResponseFlow do
  @moduledoc "Decides, applies, and records one selected participation candidate."

  use Jido.Flow,
    name: "delvetown_participation_response",
    extensions: [JidoDelvetown.Flow.Imp],
    schema: Zoi.object(%{cycle: Zoi.map()}),
    output_schema: Zoi.map()

  flow do
    imp "decide",
      input: input(:cycle)

    step "apply_decision",
      action: JidoDelvetown.Actions.ApplyDecision,
      params: %{cycle: result("decide")}

    step "record_state",
      action: JidoDelvetown.Actions.RecordCycle,
      params: %{cycle: result("apply_decision")}

    output result("record_state")
  end
end
