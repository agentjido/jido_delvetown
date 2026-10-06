defmodule JidoDelvetown.InteractionLedgerTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias JidoDelvetown.FriendList
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

  test "a repeated observation preserves a completed decision payload" do
    event_key = "event:completed-draft"

    assert {:ok, %InteractionEvent{state: "pending"}} =
             Ledger.observe(%{
               event_key: event_key,
               kind: "reply",
               payload: %{
                 action: "reply",
                 cycle_status: "simulated",
                 text: "Keep this exact draft."
               }
             })

    assert {:ok, %InteractionEvent{state: "claimed"}} = Ledger.claim(event_key)
    assert {:ok, %InteractionEvent{state: "completed"}} = Ledger.finish(event_key, :completed)

    assert {:ok, %InteractionEvent{state: "completed"}} =
             Ledger.observe(%{
               event_key: event_key,
               kind: "reply",
               payload: %{raw_reason: "reply"}
             })

    assert Ledger.event(event_key).payload == %{
             "action" => "reply",
             "cycle_status" => "simulated",
             "text" => "Keep this exact draft."
           }
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
        cid: "reply-cid",
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
             event =
             Repo.one!(
               from(event in InteractionEvent, where: event.source_id == "notification-1")
             )

    assert event.payload["publication_target"] == %{
             "cid" => "reply-cid",
             "root" => %{
               "cid" => "root-cid",
               "uri" => "at://did:plc:root/town.delve.feed.post/root"
             },
             "uri" => "at://did:plc:member/town.delve.feed.post/reply"
           }
  end

  test "a recorded response counts a friend reference once" do
    assert {:ok, _friend} =
             FriendList.add(%{did: "did:plc:friend", handle: "friend.delve.town"})

    cycle = %{
      kind: "reactive",
      mode: "normal",
      intent: "answer_direct_request",
      status: "simulated",
      errors: [],
      defer?: false,
      candidate: %{
        id: "notification-friend-reference",
        uri: "at://did:plc:member/town.delve.feed.post/reply",
        cid: "reply-cid",
        indexed_at: "2026-10-05T11:59:00Z",
        author: %{did: "did:plc:member", handle: "member.test"},
        root: %{uri: "at://did:plc:root/town.delve.feed.post/root", cid: "root-cid"}
      }
    }

    decision = %{action: "reply", text: "Ask @friend.delve.town."}

    assert :ok = Ledger.record_cycle(cycle, decision, "2026-10-05T12:00:00Z")
    assert :ok = Ledger.record_cycle(cycle, decision, "2026-10-05T12:00:00Z")
    assert FriendList.get("did:plc:friend").reference_count == 1
  end

  test "records a manual publication on a completed event" do
    now = ~U[2026-10-05 12:00:00.000000Z]

    Repo.insert!(%InteractionEvent{
      event_key: "event:manual-publication",
      kind: "reply",
      state: "completed",
      payload: %{"action" => "reply", "cycle_status" => "simulated"},
      occurred_at: now,
      terminal_at: now
    })

    assert {:ok, event} =
             Ledger.record_manual_publication("event:manual-publication", %{
               status: "completed",
               uri: "at://did:plc:bot/town.delve.feed.post/reply"
             })

    assert event.payload["manual_publication"] == %{
             "status" => "completed",
             "uri" => "at://did:plc:bot/town.delve.feed.post/reply"
           }
  end

  test "a simulated welcome counts as local outreach without an effect" do
    completed_at = "2026-10-05T12:00:00Z"
    since = ~U[2026-10-05 00:00:00Z]

    cycle = %{
      kind: "members",
      mode: "normal",
      intent: "welcome_new_member",
      status: "simulated",
      errors: [],
      defer?: false,
      candidate: %{
        id: "did:plc:simulated-member",
        event_key: "member:simulated",
        uri: nil,
        indexed_at: "2026-10-05T11:59:00Z",
        author: %{
          did: "did:plc:simulated-member",
          handle: "simulated-member.test",
          display_name: "Simulated Member"
        },
        root: nil
      }
    }

    assert :ok = Ledger.record_cycle(cycle, %{action: "welcome"}, completed_at)
    assert :ok = Ledger.record_cycle(cycle, %{action: "welcome"}, completed_at)

    assert Ledger.outreach_count("welcome", since) == 1
    assert Repo.aggregate(Effect, :count, :operation_key) == 0

    assert %Actor{contact_count: 1, welcome_status: "simulated"} =
             Ledger.actor("did:plc:simulated-member")
  end

  test "a simulated like persists its daily count and actor cooldown" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    since = DateTime.add(now, -1, :hour)
    actor_did = "did:plc:liked-author"

    cycle = %{
      kind: "proactive",
      mode: "normal",
      intent: "join_useful_discussion",
      status: "simulated",
      errors: [],
      defer?: false,
      selection: %{reason: "useful discussion scored 83", score: 83},
      state: %{budget: %{date: "2026-10-05", likes: 2}},
      candidate: %{
        id: "at://did:plc:liked-author/town.delve.feed.post/one",
        uri: "at://did:plc:liked-author/town.delve.feed.post/one",
        cid: "post-cid",
        text: String.duplicate("x", 600),
        indexed_at: DateTime.to_iso8601(now),
        author: %{did: actor_did, handle: "liked-author.test"},
        root: nil
      }
    }

    assert :ok = Ledger.record_cycle(cycle, %{action: "like"}, DateTime.to_iso8601(now))
    event = Repo.get_by!(InteractionEvent, record_uri: cycle.candidate.uri)

    assert Ledger.outreach_count("like", since) == 1
    assert Ledger.recent_outreach_for_actor?("like", actor_did, since)
    assert Ledger.outreach_count("like", since, exclude_event_key: event.event_key) == 0

    refute Ledger.recent_outreach_for_actor?(
             "like",
             actor_did,
             since,
             exclude_event_key: event.event_key
           )

    assert event.payload["like_review"]["author"]["handle"] == "liked-author.test"
    assert String.length(event.payload["like_review"]["post_text"]) == 500
    assert event.payload["like_review"]["selected_at"] == DateTime.to_iso8601(now)

    assert event.payload["like_review"]["budget"] == %{
             "date" => "2026-10-05",
             "likes" => 2,
             "limit" => 5,
             "remaining" => 3
           }

    refute Ledger.recent_outreach_for_actor?(
             "like",
             actor_did,
             DateTime.add(now, 1, :hour)
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
      status: "completed",
      attempt_count: 1,
      receipt: %{"uri" => "at://receipt"},
      reserved_at: now,
      completed_at: now
    }
    |> Repo.insert!()
  end
end
