defmodule JidoDelvetown.InteractionLedgerTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias JidoDelvetown.InteractionLedger, as: Ledger
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{Actor, Conversation, Effect, InteractionEvent}

  setup do
    Repo.delete_all(InteractionEvent)
    Repo.delete_all(Conversation)
    Repo.delete_all(Actor)
    Repo.delete_all(Effect)
    :ok
  end

  test "one caller claims an observed event" do
    assert {:ok, %InteractionEvent{state: "pending"}} =
             Ledger.observe(%{event_key: "event:atomic", kind: "reply"})

    results =
      1..12
      |> Task.async_stream(fn _index -> Ledger.claim("event:atomic") end, max_concurrency: 12)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, %InteractionEvent{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, {:not_claimable, "claimed"}}, &1)) == 11
    assert Ledger.event("event:atomic").attempt_count == 1
  end

  test "pending claimed and terminal states survive caller exit" do
    task =
      Task.async(fn ->
        Ledger.observe(%{event_key: "event:restart", kind: "mention"})
      end)

    assert {:ok, %InteractionEvent{state: "pending"}} = Task.await(task)
    assert {:ok, %InteractionEvent{state: "claimed"}} = Ledger.claim("event:restart")

    assert {:ok, 1} = Ledger.recover_stale_claims(stale_after_ms: 0)
    assert Ledger.event("event:restart").state == "pending"
    assert {:ok, %InteractionEvent{attempt_count: 2}} = Ledger.claim("event:restart")

    assert {:ok, %InteractionEvent{state: "completed"}} =
             Ledger.finish("event:restart", :completed)

    assert {:ok, 0} = Ledger.recover_stale_claims(stale_after_ms: 0)
    assert {:error, {:not_claimable, "completed"}} = Ledger.claim("event:restart")
  end

  test "a recorded reply updates actor and conversation memory once" do
    completed_at = "2026-10-05T12:00:00Z"

    cycle = %{
      kind: "reactive",
      mode: "normal",
      intent: "answer_direct_request",
      status: "acted",
      errors: [],
      defer?: false,
      candidate: %{
        id: "notification-1",
        uri: "at://did:plc:member/town.delve.feed.post/reply",
        indexed_at: "2026-10-05T11:59:00Z",
        author: %{did: "did:plc:member", handle: "member.test", display_name: "Member"},
        root: %{uri: "at://did:plc:root/town.delve.feed.post/root", cid: "root-cid"}
      }
    }

    decision = %{action: "reply"}

    assert :ok = Ledger.record_cycle(cycle, decision, completed_at)
    assert :ok = Ledger.record_cycle(cycle, decision, completed_at)

    assert %Actor{contact_count: 1, handle: "member.test"} = Ledger.actor("did:plc:member")

    assert %Conversation{turn_count: 1, last_action: "reply"} =
             Ledger.conversation("at://did:plc:root/town.delve.feed.post/root")

    assert %InteractionEvent{state: "completed", attempt_count: 1} =
             Repo.one!(
               from(event in InteractionEvent, where: event.source_id == "notification-1")
             )
  end

  test "retention removes old terminal events but keeps effect receipts" do
    now = ~U[2026-10-05 12:00:00.000000Z]
    old = ~U[2025-01-01 12:00:00.000000Z]

    assert {:ok, _event} =
             Ledger.observe(%{event_key: "event:old", kind: "reply", occurred_at: old})

    assert {:ok, _event} = Ledger.claim("event:old")
    assert {:ok, _event} = Ledger.finish("event:old", :completed)

    Repo.update_all(
      from(event in InteractionEvent, where: event.event_key == "event:old"),
      set: [terminal_at: old]
    )

    insert_effect(now)

    assert {:ok, %{expired: 1, overflow: 0}} =
             Ledger.prune(now: now, retention_days: 90, event_limit: 100)

    assert is_nil(Ledger.event("event:old"))
    assert %Effect{receipt: %{"uri" => "at://receipt"}} = Repo.get(Effect, "reply:stable")
  end

  defp insert_effect(now) do
    %Effect{
      operation_key: "reply:stable",
      kind: "reply",
      collection: "town.delve.feed.post",
      rkey: "stable-rkey",
      status: "complete",
      attempt_count: 1,
      receipt: %{"uri" => "at://receipt"},
      reserved_at: now,
      completed_at: now
    }
    |> Repo.insert!()
  end
end
