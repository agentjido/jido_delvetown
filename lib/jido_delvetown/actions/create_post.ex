defmodule JidoDelvetown.Actions.CreatePost do
  @moduledoc "Creates one top-level Delvetown post."

  use Jido.Action,
    name: "delvetown_create_post",
    description: "Create one top-level Delvetown post.",
    schema:
      Zoi.object(%{
        text: Zoi.string(description: "Post text") |> Zoi.min(1) |> Zoi.max(300),
        langs:
          Zoi.list(Zoi.string(), description: "BCP-47 language tags")
          |> Zoi.max(3)
          |> Zoi.default(["en"])
      })

  @impl true
  def run(%{text: text, langs: langs}, _context) do
    hour = DateTime.utc_now() |> Calendar.strftime("%Y-%m-%dT%H")
    key = JidoDelvetown.Protocol.effect_key("post", [text, hour])

    JidoDelvetown.Protocol.create_record(key, "town.delve.feed.post", %{
      text: text,
      langs: langs,
      created_at: JidoDelvetown.Protocol.now()
    })
  end
end
