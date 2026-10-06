defmodule JidoDelvetown.Actions.FollowActor do
  @moduledoc "Follows one Delvetown actor."

  use Jido.Action,
    name: "delvetown_follow_actor",
    description: "Follow one actor. The subject must be a DID from a profile response.",
    schema: Zoi.object(%{did: Zoi.string(description: "Actor DID") |> Zoi.min(1)})

  @impl true
  def run(%{did: did}, context) do
    key = JidoDelvetown.Protocol.effect_key("follow", [did])

    with {:ok, result} <-
           JidoDelvetown.Protocol.create_record(
             key,
             "town.delve.graph.follow",
             %{
               subject: did,
               created_at: JidoDelvetown.Protocol.now()
             },
             subject_key: did,
             actor_did: did,
             settings: Map.get(context, :settings)
           ),
         {:ok, _relationship} <- JidoDelvetown.FriendList.record_agent_follows(did) do
      {:ok, result}
    end
  end
end
