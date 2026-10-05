defmodule JidoDelvetown.Actions.GetProfile do
  @moduledoc "Gets one Delvetown actor profile."

  use Jido.Action,
    name: "delvetown_get_profile",
    description: "Get one actor profile by DID or handle.",
    schema: Zoi.object(%{actor: Zoi.string(description: "Actor DID or handle") |> Zoi.min(1)})

  @impl true
  def run(params, _context) do
    JidoDelvetown.Protocol.query("town.delve.actor.getProfile", params)
  end
end
