defmodule JidoDelvetown.Actions.UpdateNotificationsSeen do
  @moduledoc "Marks Delvetown notifications seen through the current time."

  use Jido.Action,
    name: "delvetown_update_notifications_seen",
    description: "Mark notifications seen after the participation cycle is complete.",
    schema: Zoi.object(%{})

  @impl true
  def run(_params, _context) do
    JidoDelvetown.Protocol.notification_procedure(
      "town.delve.notification.updateSeen",
      %{seen_at: JidoDelvetown.Protocol.now()}
    )
  end
end
