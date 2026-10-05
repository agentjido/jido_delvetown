defmodule JidoDelvetown.Actions.WelcomeActor do
  @moduledoc "Publishes one idempotent welcome for a DelveTown actor."

  use Jido.Action,
    name: "delvetown_welcome_actor",
    description: "Publish one useful welcome for an actor DID.",
    schema:
      Zoi.object(%{
        did: Zoi.string(description: "Actor DID") |> Zoi.min(1),
        text: Zoi.string(description: "Welcome text") |> Zoi.min(1) |> Zoi.max(300),
        langs: Zoi.list(Zoi.string()) |> Zoi.max(3) |> Zoi.default(["en"])
      })

  @impl true
  def run(%{did: did, text: text, langs: langs}, _context) do
    key = JidoDelvetown.Protocol.effect_key("welcome", [did])

    JidoDelvetown.Protocol.create_record(
      key,
      "town.delve.feed.post",
      %{
        text: text,
        langs: langs,
        created_at: JidoDelvetown.Protocol.now()
      },
      subject_key: did,
      actor_did: did
    )
  end
end
