defmodule JidoDelvetown.Actions.WelcomeActor do
  @moduledoc "Publishes one idempotent welcome for a DelveTown actor."

  use Jido.Action,
    name: "delvetown_welcome_actor",
    description: "Publish one useful welcome for an actor DID.",
    schema:
      Zoi.object(%{
        did: Zoi.string(description: "Actor DID") |> Zoi.min(1),
        handle: Zoi.string(description: "Verified actor handle") |> Zoi.min(1),
        text: Zoi.string(description: "Welcome text") |> Zoi.min(1) |> Zoi.max(300),
        target: Zoi.map() |> Zoi.optional()
      })

  @impl true
  def run(%{did: did, handle: handle, text: text} = params, _context) do
    key = JidoDelvetown.Protocol.effect_key("welcome", [did])

    with {:ok, record} <-
           JidoDelvetown.WelcomePost.record(text, did, handle, Map.get(params, :target)) do
      JidoDelvetown.Protocol.create_record(
        key,
        "town.delve.feed.post",
        record,
        subject_key: did,
        actor_did: did
      )
    end
  end
end
