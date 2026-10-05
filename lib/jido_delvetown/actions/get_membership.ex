defmodule JidoDelvetown.Actions.GetMembership do
  @moduledoc "Gets the Delvetown membership state for the signed-in account."

  use Jido.Action,
    name: "delvetown_get_membership",
    description: "Get the signed-in account's Delvetown membership state.",
    schema: Zoi.object(%{})

  @impl true
  def run(_params, _context) do
    JidoDelvetown.Protocol.query("town.delve.membership.getMembership", %{})
  end
end
