defmodule JidoDelvetown.Actions.GetAuthorFeed do
  @moduledoc "Gets one actor's Delvetown feed."

  use Jido.Action,
    name: "delvetown_get_author_feed",
    description: "Get recent posts for one actor DID or handle.",
    schema:
      Zoi.object(%{
        actor: Zoi.string(description: "Actor DID or handle") |> Zoi.min(1),
        cursor: Zoi.string(description: "Cursor from the prior page") |> Zoi.optional(),
        filter:
          Zoi.string(description: "Optional server-supported feed filter") |> Zoi.optional(),
        limit: Zoi.integer() |> Zoi.min(1) |> Zoi.max(100) |> Zoi.default(25)
      })

  @impl true
  def run(params, _context) do
    JidoDelvetown.Protocol.query("town.delve.feed.getAuthorFeed", params)
  end
end
