defmodule JidoDelvetown.Actions.DeleteRecord do
  @moduledoc "Deletes one protocol record owned by the signed-in account."

  use Jido.Action,
    name: "delvetown_delete_own_record",
    description:
      "Delete an owned post, like, repost, or follow record by its full AT URI. This cannot delete another account's record.",
    schema:
      Zoi.object(%{uri: Zoi.string(description: "Full AT URI of the owned record") |> Zoi.min(1)})

  @impl true
  def run(%{uri: uri}, _context) do
    JidoDelvetown.Protocol.delete_own_record(uri)
  end
end
