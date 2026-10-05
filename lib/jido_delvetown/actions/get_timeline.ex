defmodule JidoDelvetown.Actions.GetTimeline do
  @moduledoc "Gets the signed-in account's Delvetown timeline."

  use Jido.Action,
    name: "delvetown_get_timeline",
    description: "Get a page from the signed-in account's Delvetown timeline.",
    schema:
      Zoi.object(%{
        cursor: Zoi.string(description: "Cursor from the prior page") |> Zoi.optional(),
        limit: Zoi.integer() |> Zoi.min(1) |> Zoi.max(100) |> Zoi.default(25)
      })

  @impl true
  def run(params, _context) do
    JidoDelvetown.Protocol.query("town.delve.feed.getTimeline", params)
  end
end
