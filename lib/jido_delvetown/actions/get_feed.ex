defmodule JidoDelvetown.Actions.GetFeed do
  @moduledoc "Gets one Delvetown feed."

  use Jido.Action,
    name: "delvetown_get_feed",
    description: "Get a page from one Delvetown feed URI.",
    schema:
      Zoi.object(%{
        feed: Zoi.string(description: "AT URI of the feed") |> Zoi.min(1),
        cursor: Zoi.string(description: "Cursor from the prior page") |> Zoi.optional(),
        limit: Zoi.integer() |> Zoi.min(1) |> Zoi.max(100) |> Zoi.default(25)
      })

  @impl true
  def run(params, _context) do
    JidoDelvetown.Protocol.query("town.delve.feed.getFeed", params)
  end
end
