defmodule JidoDelvetown.Actions.GetPosts do
  @moduledoc "Gets Delvetown post views for a list of AT URIs."

  use Jido.Action,
    name: "delvetown_get_posts",
    description: "Get post views for one or more AT URIs.",
    schema:
      Zoi.object(%{
        uris:
          Zoi.list(Zoi.string(description: "Post AT URI"), description: "Post AT URIs")
          |> Zoi.min(1)
          |> Zoi.max(25)
      })

  @impl true
  def run(params, _context) do
    JidoDelvetown.Protocol.query("town.delve.feed.getPosts", params)
  end
end
