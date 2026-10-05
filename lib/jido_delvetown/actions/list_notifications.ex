defmodule JidoDelvetown.Actions.ListNotifications do
  @moduledoc "Lists a bounded page of Delvetown notifications."

  use Jido.Action,
    name: "delvetown_list_notifications",
    description: "List notifications. Use the returned cursor to read the next page.",
    schema:
      Zoi.object(%{
        cursor: Zoi.string(description: "Cursor from the prior page") |> Zoi.optional(),
        limit:
          Zoi.integer(description: "Maximum number of notifications")
          |> Zoi.min(1)
          |> Zoi.max(100)
          |> Zoi.default(20)
      })

  @impl true
  def run(params, _context) do
    JidoDelvetown.Protocol.query("town.delve.notification.listNotifications", params)
  end
end
