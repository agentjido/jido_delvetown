defmodule JidoDelvetown.EventNormalizationTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{Candidate, InteractionLedger, Repo}
  alias JidoDelvetown.Storage.InteractionEvent

  setup do
    Repo.delete_all(InteractionEvent)
    :ok
  end

  test "normalizes replies mentions and follows with protocol identities" do
    candidates =
      Candidate.notifications(%{
        "notifications" => [
          notification("event-reply", "replied"),
          notification("event-mention", "mentioned"),
          notification("event-follow", "new_follow", uri: nil, cid: nil)
        ]
      })

    assert Enum.map(candidates, & &1.reason) == ["reply", "mention", "follow"]

    assert Enum.map(candidates, & &1.event_key) == [
             "notification:event-reply",
             "notification:event-mention",
             "notification:event-follow"
           ]

    assert Enum.all?(candidates, &(&1.author.did == "did:plc:member"))
    assert Enum.all?(candidates, &(&1.indexed_at == "2026-10-05T12:00:00Z"))
  end

  test "duplicate and overlapping pages create one durable event" do
    [candidate] =
      Candidate.notifications(%{
        "notifications" => [notification("event-overlap", "reply")]
      })

    assert :ok = InteractionLedger.observe_candidates([candidate])
    assert :ok = InteractionLedger.observe_candidates([candidate, candidate])

    assert Repo.aggregate(InteractionEvent, :count, :event_key) == 1

    assert %InteractionEvent{
             event_key: "notification:event-overlap",
             kind: "reply",
             actor_did: "did:plc:member",
             source_id: "event-overlap"
           } = InteractionLedger.event(candidate.event_key)
  end

  test "event identities do not change when a page is reordered" do
    first = [notification(nil, "reply"), notification("event-follow", "follow", uri: nil)]
    second = Enum.reverse(first)

    first_keys = first |> candidates() |> Enum.map(& &1.event_key) |> MapSet.new()
    second_keys = second |> candidates() |> Enum.map(& &1.event_key) |> MapSet.new()

    assert first_keys == second_keys
  end

  test "missing optional fields produce a stable follow event" do
    [candidate] =
      Candidate.notifications(%{
        "notifications" => [
          %{
            "id" => "event-minimal-follow",
            "reason" => "follow",
            "author" => %{"did" => "did:plc:new-member"}
          }
        ]
      })

    assert candidate.id == "event-minimal-follow"
    assert candidate.event_key == "notification:event-minimal-follow"
    assert candidate.reason == "follow"
    assert candidate.author == %{did: "did:plc:new-member"}
    assert candidate.uri == nil
    assert candidate.text == ""
    assert candidate.parent == nil
    assert candidate.root == nil
  end

  test "an empty protocol identifier uses immutable source fields" do
    item = notification("", "mention")
    [candidate] = candidates([item])

    assert String.starts_with?(candidate.event_key, "notification:")
    refute candidate.event_key == "notification:"
    assert candidate.protocol_id == nil
  end

  defp candidates(items), do: Candidate.notifications(%{"notifications" => items})

  defp notification(id, reason, opts \\ []) do
    uri = Keyword.get(opts, :uri, "at://did:plc:member/town.delve.feed.post/one")
    cid = Keyword.get(opts, :cid, "cid-one")

    %{
      "id" => id,
      "uri" => uri,
      "cid" => cid,
      "reason" => reason,
      "isRead" => false,
      "indexedAt" => "2026-10-05T12:00:00Z",
      "author" => %{"did" => "did:plc:member", "handle" => "member.test"},
      "record" => %{"text" => "Hello AgentJido"}
    }
  end
end
