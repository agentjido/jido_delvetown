defmodule JidoDelvetown.Flow.ImpTest.ExampleFlow do
  @moduledoc false

  use Jido.Flow,
    name: "imp_extension_example",
    extensions: [JidoDelvetown.Flow.Imp]

  flow do
    imp "predict",
      input: input(:value)

    output result("predict")
  end
end

defmodule JidoDelvetown.Flow.ImpTest do
  use ExUnit.Case, async: true

  alias JidoDelvetown.Actions.DecideParticipation
  alias JidoDelvetown.Flow.ImpTest.ExampleFlow

  test "imp lowers to a normal Jido Action step" do
    assert [
             %Jido.Flow.Step{
               name: "predict",
               action: DecideParticipation,
               params: %{
                 cycle: %Jido.Flow.Ref{source: :input, path: [:value]}
               }
             }
           ] = ExampleFlow.flow().components
  end

  test "the shared response Flow declares its decision as an imp step" do
    assert %Jido.Flow.Step{
             action: DecideParticipation,
             params: %{
               cycle: %Jido.Flow.Ref{source: :input, path: [:cycle]}
             }
           } =
             Enum.find(
               JidoDelvetown.ParticipationResponseFlow.flow().components,
               &(&1.name == "decide")
             )
  end

  test "reactive and proactive Flows share the response sub-flow" do
    for flow <- [
          JidoDelvetown.ReactiveParticipationCycle,
          JidoDelvetown.ProactiveParticipationCycle
        ] do
      assert %Jido.Flow.Subflow{flow: JidoDelvetown.ParticipationResponseFlow} =
               Enum.find(flow.flow().components, &(&1.name == "respond"))
    end
  end
end
