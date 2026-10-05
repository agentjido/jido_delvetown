defmodule JidoDelvetown.InspectionTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{Inspection, Repo}

  alias JidoDelvetown.Storage.{
    Actor,
    AuditEvent,
    Conversation,
    Effect,
    InteractionEvent,
    LegacyImport,
    ScanState
  }

  setup do
    clear_inspection_tables()
    on_exit(&clear_inspection_tables/0)

    :ok
  end

  test "an empty snapshot has stable zero counts and current migrations" do
    snapshot = Inspection.snapshot()

    assert snapshot.events.counts == %{
             "claimed" => 0,
             "completed" => 0,
             "failed" => 0,
             "ignored" => 0,
             "pending" => 0
           }

    assert snapshot.effects.counts == %{
             "completed" => 0,
             "permanent_failure" => 0,
             "reserved" => 0,
             "uncertain" => 0
           }

    assert snapshot.actors.recent == []
    assert snapshot.scans == []
    assert snapshot.effects.completed_receipts == []
    assert snapshot.sqlite.migrations.status == "current"
    assert snapshot.sqlite.migrations.pending == []
    assert snapshot.sqlite.legacy_imports == []
  end

  test "active memory exposes bounded actor, conversation, scan, and receipt fields" do
    now = ~U[2026-10-05 12:00:00.000000Z]

    Repo.insert!(%InteractionEvent{
      event_key: "event:active",
      kind: "mention",
      actor_did: "did:plc:member",
      occurred_at: now,
      state: "completed",
      payload: %{"private_model_context" => "must stay hidden"},
      terminal_at: now
    })

    Repo.insert!(%Actor{
      did: "did:plc:member",
      handle: "member.test",
      display_name: "Member",
      profile: %{"private" => "profile data"},
      first_seen_at: now,
      last_seen_at: now,
      last_interaction_at: now,
      contact_count: 2,
      welcome_status: "completed",
      metadata: %{"private" => "actor notes"}
    })

    Repo.insert!(%Conversation{
      root_uri: "at://did:plc:member/town.delve.feed.post/root",
      actor_did: "did:plc:member",
      turn_count: 2,
      last_record_uri: "at://did:plc:member/town.delve.feed.post/reply",
      last_action: "reply",
      last_action_at: now,
      metadata: %{"private" => "conversation notes"}
    })

    Repo.insert!(%ScanState{
      name: "notifications",
      cursor: "cursor-2",
      metadata: %{
        "last_completed_at" => "2026-10-05T12:00:00Z",
        "lease_token" => "private-token"
      }
    })

    Repo.insert!(
      effect("reply:complete", "completed", now, %{
        "uri" => "at://receipt",
        "cid" => "bafy",
        "private" => "hidden"
      })
    )

    snapshot = Inspection.snapshot()

    assert snapshot.events.counts["completed"] == 1
    assert [%{handle: "member.test", contact_count: 2} = actor] = snapshot.actors.recent
    refute Map.has_key?(actor, :profile)
    refute Map.has_key?(actor, :metadata)
    assert [%{turn_count: 2}] = snapshot.conversations.recent

    assert [scan] = snapshot.scans
    assert scan.cursor == "cursor-2"
    refute Map.has_key?(scan, :metadata)
    refute inspect(scan) =~ "private-token"

    assert [receipt] = snapshot.effects.completed_receipts
    assert receipt.receipt == %{uri: "at://receipt", cid: "bafy"}
    refute inspect(snapshot) =~ "must stay hidden"
    refute inspect(snapshot) =~ "profile data"
    refute inspect(snapshot) =~ "actor notes"
    refute inspect(snapshot) =~ "conversation notes"
    refute inspect(snapshot) =~ "private-token"
  end

  test "reserved, uncertain, and permanently failed effects need attention" do
    now = ~U[2026-10-05 12:00:00.000000Z]

    Repo.insert!(effect("like:reserved", "reserved", now))
    Repo.insert!(effect("reply:uncertain", "uncertain", now))

    Repo.insert!(
      effect("follow:failed", "permanent_failure", now)
      |> Map.put(:failure, %{"reason" => "private transport failure"})
    )

    snapshot = Inspection.snapshot()

    assert snapshot.effects.counts["reserved"] == 1
    assert snapshot.effects.counts["uncertain"] == 1
    assert snapshot.effects.counts["permanent_failure"] == 1

    assert Enum.map(snapshot.effects.attention, & &1.status) |> Enum.sort() ==
             ["permanent_failure", "reserved", "uncertain"]

    assert Enum.find(snapshot.effects.attention, &(&1.status == "permanent_failure")).failure_present?
    refute inspect(snapshot) =~ "private transport failure"
  end

  test "reconciled effects and legacy import status are visible" do
    now = ~U[2026-10-05 12:00:00.000000Z]

    Repo.insert!(%AuditEvent{
      type: "create_record",
      data: %{"reconciled?" => true, "private" => "hidden audit data"},
      occurred_at: now
    })

    Repo.insert!(%LegacyImport{
      name: "dets-and-file-v1",
      checksum: "checksum",
      status: "complete",
      details: %{"effects" => 3, "unknown_private_field" => "hidden"},
      imported_at: now
    })

    snapshot = Inspection.snapshot()

    assert snapshot.effects.reconciled == 1

    assert [legacy] = snapshot.sqlite.legacy_imports
    assert legacy.status == "complete"
    assert legacy.counts["effects"] == 3
    refute inspect(snapshot) =~ "hidden audit data"
    refute inspect(snapshot) =~ "unknown_private_field"
  end

  defp effect(key, status, now, receipt \\ nil) do
    %Effect{
      operation_key: key,
      kind: key |> String.split(":", parts: 2) |> hd(),
      collection: "town.delve.feed.post",
      rkey: String.replace(key, ":", "-"),
      status: status,
      attempt_count: 1,
      receipt: receipt,
      reserved_at: now,
      completed_at: if(status in ["completed", "permanent_failure"], do: now)
    }
  end

  defp clear_inspection_tables do
    Enum.each(
      [AuditEvent, Effect, Conversation, Actor, InteractionEvent, ScanState, LegacyImport],
      &Repo.delete_all/1
    )
  end
end
