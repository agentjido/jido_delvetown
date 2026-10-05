defmodule JidoDelvetown.Actions.GetPostThread do
  @moduledoc "Gets a Delvetown post and its thread context."

  use Jido.Action,
    name: "delvetown_get_post_thread",
    description: "Get a post, its parent context, and replies. Read this before replying.",
    schema:
      Zoi.object(%{
        uri: Zoi.string(description: "AT URI of the post") |> Zoi.min(1),
        depth: Zoi.integer() |> Zoi.min(0) |> Zoi.max(100) |> Zoi.default(12),
        parent_height: Zoi.integer() |> Zoi.min(0) |> Zoi.max(100) |> Zoi.default(12)
      })

  @impl true
  def run(params, _context) do
    JidoDelvetown.Protocol.query("town.delve.feed.getPostThread", params)
  end
end
