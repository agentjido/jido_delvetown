defmodule JidoDelvetown.Actions.SearchPosts do
  @moduledoc "Searches Delvetown posts."

  use Jido.Action,
    name: "delvetown_search_posts",
    description: "Search Delvetown posts with a bounded result count.",
    schema:
      Zoi.object(%{
        q: Zoi.string(description: "Search query") |> Zoi.min(1) |> Zoi.max(500),
        cursor: Zoi.string(description: "Cursor from the prior page") |> Zoi.optional(),
        sort: Zoi.enum(["top", "latest"]) |> Zoi.default("latest"),
        limit: Zoi.integer() |> Zoi.min(1) |> Zoi.max(100) |> Zoi.default(25)
      })

  @impl true
  def run(params, _context) do
    JidoDelvetown.Protocol.query("town.delve.feed.searchPosts", params)
  end
end
