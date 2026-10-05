defmodule JidoDelvetown.Actions.CreatePost do
  @moduledoc "Creates one top-level Delvetown post."

  use Jido.Action,
    name: "delvetown_create_post",
    description: "Create one top-level Delvetown post.",
    schema:
      Zoi.object(%{
        opportunity_id:
          Zoi.string(description: "Stable identifier for this posting opportunity")
          |> Zoi.min(1),
        text: Zoi.string(description: "Post text") |> Zoi.min(1) |> Zoi.max(300),
        langs:
          Zoi.list(Zoi.string(), description: "BCP-47 language tags")
          |> Zoi.max(3)
          |> Zoi.default(["en"])
      })

  @impl true
  def run(%{opportunity_id: opportunity_id, text: text, langs: langs}, _context) do
    key = JidoDelvetown.Protocol.effect_key("post", [opportunity_id])

    JidoDelvetown.Protocol.create_record(
      key,
      "town.delve.feed.post",
      %{
        text: text,
        langs: langs,
        created_at: JidoDelvetown.Protocol.now()
      },
      subject_key: opportunity_id
    )
  end
end
