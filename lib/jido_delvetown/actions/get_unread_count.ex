defmodule JidoDelvetown.Actions.GetUnreadCount do
  @moduledoc "Gets the unread Delvetown notification count."

  use Jido.Action,
    name: "delvetown_get_unread_count",
    description: "Get the unread Delvetown notification count.",
    schema: Zoi.object(%{})

  @impl true
  def run(_params, _context) do
    JidoDelvetown.Protocol.query("town.delve.notification.getUnreadCount", %{})
  end
end
