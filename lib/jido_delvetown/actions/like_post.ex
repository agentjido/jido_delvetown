defmodule JidoDelvetown.Actions.LikePost do
  @moduledoc "Likes one Delvetown post."

  use Jido.Action,
    name: "delvetown_like_post",
    description: "Like one post by its AT URI and CID.",
    schema:
      Zoi.object(%{
        uri: Zoi.string(description: "Post AT URI") |> Zoi.min(1),
        cid: Zoi.string(description: "Post CID") |> Zoi.min(1)
      })

  @impl true
  def run(%{uri: uri, cid: cid}, _context) do
    key = JidoDelvetown.Protocol.effect_key("like", [uri])

    JidoDelvetown.Protocol.create_record(
      key,
      "town.delve.feed.like",
      %{
        subject: %{uri: uri, cid: cid},
        created_at: JidoDelvetown.Protocol.now()
      },
      subject_key: uri
    )
  end
end
