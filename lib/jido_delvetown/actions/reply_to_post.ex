defmodule JidoDelvetown.Actions.ReplyToPost do
  @moduledoc "Creates one reply to a Delvetown post."

  use Jido.Action,
    name: "delvetown_reply_to_post",
    description: "Reply after reading the full thread. Use strong references from post views.",
    schema:
      Zoi.object(%{
        text: Zoi.string(description: "Reply text") |> Zoi.min(1) |> Zoi.max(300),
        parent_uri: Zoi.string(description: "Parent post AT URI") |> Zoi.min(1),
        parent_cid: Zoi.string(description: "Parent post CID") |> Zoi.min(1),
        root_uri: Zoi.string(description: "Root post AT URI") |> Zoi.min(1),
        root_cid: Zoi.string(description: "Root post CID") |> Zoi.min(1),
        langs: Zoi.list(Zoi.string()) |> Zoi.max(3) |> Zoi.default(["en"])
      })

  @impl true
  def run(params, context) do
    key = JidoDelvetown.Protocol.effect_key("reply", [params.parent_uri])

    JidoDelvetown.Protocol.create_record(
      key,
      "town.delve.feed.post",
      %{
        text: params.text,
        langs: params.langs,
        created_at: JidoDelvetown.Protocol.now(),
        reply: %{
          root: %{uri: params.root_uri, cid: params.root_cid},
          parent: %{uri: params.parent_uri, cid: params.parent_cid}
        }
      },
      subject_key: params.parent_uri,
      settings: Map.get(context, :settings)
    )
  end
end
