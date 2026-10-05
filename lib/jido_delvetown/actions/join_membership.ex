defmodule JidoDelvetown.Actions.JoinMembership do
  @moduledoc "Joins Delvetown with the configured invite code."

  use Jido.Action,
    name: "delvetown_join_membership",
    description: "Join Delvetown with the operator-configured invite code.",
    schema: Zoi.object(%{})

  @impl true
  def run(_params, _context) do
    body =
      case JidoDelvetown.Config.invite_code() do
        {:ok, invite_code} -> %{invite_code: invite_code}
        {:error, _reason} -> %{}
      end

    JidoDelvetown.Protocol.procedure("town.delve.membership.join", body)
  end
end
