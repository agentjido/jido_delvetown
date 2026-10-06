defmodule JidoDelvetown.CycleRecorderTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{ActorMemory, ConversationMemory, CycleRecorder, Repo}

  alias JidoDelvetown.Storage.{
    Actor,
    ActorRelationship,
    Conversation,
    Effect,
    InteractionEvent
  }

  setup do
    Repo.delete_all(ActorRelationship)
    Repo.delete_all(InteractionEvent)
    Repo.delete_all(Conversation)
    Repo.delete_all(Actor)
    Repo.delete_all(Effect)
    :ok
  end

  test "records one completed decision when the cycle is retried" do
    cycle = reply_cycle("event:reply-once")

    assert :ok = CycleRecorder.record(cycle, %{action: "reply"}, completed_at())
    assert :ok = CycleRecorder.record(cycle, %{action: "reply"}, completed_at())

    assert %InteractionEvent{state: "completed", attempt_count: 1} =
             Repo.get(InteractionEvent, "event:reply-once")

    assert %Actor{contact_count: 1} = ActorMemory.get("did:plc:member")

    assert %Conversation{turn_count: 1} =
             ConversationMemory.get(root_uri())
  end

  test "does not update memory for an event that was already terminal" do
    now = ~U[2026-10-05 12:00:00.000000Z]

    Repo.insert!(%InteractionEvent{
      event_key: "event:already-completed",
      kind: "reply",
      actor_did: "did:plc:member",
      state: "completed",
      occurred_at: now,
      terminal_at: now,
      payload: %{}
    })

    cycle = reply_cycle("event:already-completed")

    assert :ok = CycleRecorder.record(cycle, %{action: "reply"}, completed_at())

    assert %InteractionEvent{state: "completed", attempt_count: 0} =
             Repo.get(InteractionEvent, "event:already-completed")

    assert ActorMemory.get("did:plc:member") == nil
    assert ConversationMemory.get(root_uri()) == nil
  end

  defp reply_cycle(event_key) do
    %{
      kind: "reactive",
      mode: "normal",
      intent: "answer_direct_request",
      status: "acted",
      errors: [],
      defer?: false,
      candidate: %{
        id: "notification-1",
        event_key: event_key,
        reason: "reply",
        uri: "at://did:plc:member/town.delve.feed.post/reply",
        cid: "reply-cid",
        indexed_at: "2026-10-05T11:59:00Z",
        author: %{did: "did:plc:member", handle: "member.test"},
        root: %{uri: root_uri(), cid: "root-cid"}
      }
    }
  end

  defp root_uri, do: "at://did:plc:root/town.delve.feed.post/root"
  defp completed_at, do: "2026-10-05T12:00:00Z"
end
