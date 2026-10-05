defmodule JidoDelvetown.Actions.FollowActor do
  @moduledoc "Follows one Delvetown actor."

  use Jido.Action,
    name: "delvetown_follow_actor",
    description: "Follow one actor. The subject must be a DID from a profile response.",
    schema: Zoi.object(%{did: Zoi.string(description: "Actor DID") |> Zoi.min(1)})

  @impl true
  def run(%{did: did}, _context) do
    key = JidoDelvetown.Protocol.effect_key("follow", [did])

    JidoDelvetown.Protocol.create_record(
      key,
      "town.delve.graph.follow",
      %{
        subject: did,
        created_at: JidoDelvetown.Protocol.now()
      },
      subject_key: did,
      actor_did: did
    )
  end
end
