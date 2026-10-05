defmodule JidoDelvetown.Actions.ListOwnRecords do
  @moduledoc "Lists protocol records owned by the signed-in account."

  use Jido.Action,
    name: "delvetown_list_own_records",
    description:
      "List the account's posts, likes, reposts, or follows and get their record URIs.",
    schema:
      Zoi.object(%{
        collection:
          Zoi.enum([
            "town.delve.feed.post",
            "town.delve.feed.like",
            "town.delve.feed.repost",
            "town.delve.graph.follow"
          ]),
        cursor: Zoi.string(description: "Cursor from the prior page") |> Zoi.optional(),
        limit: Zoi.integer() |> Zoi.min(1) |> Zoi.max(100) |> Zoi.default(25),
        reverse: Zoi.boolean() |> Zoi.default(true)
      })

  @impl true
  def run(%{collection: collection} = params, _context) do
    JidoDelvetown.Protocol.list_own_records(collection, Map.delete(params, :collection))
  end
end
