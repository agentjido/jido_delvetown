defmodule JidoDelvetown.InspectionTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{ImageDrafts, Inspection, Repo}
  alias JidoDelvetown.Workers.ProactiveReviewWorker

  alias JidoDelvetown.Storage.{
    Actor,
    AuditEvent,
    Conversation,
    Effect,
    ImageArtifact,
    ImageDraft,
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
    assert snapshot.simulated_posts == []
    assert snapshot.image_drafts == []
    assert snapshot.scans == []
    assert snapshot.effects.completed_receipts == []
    assert snapshot.automation.proactive_review.cron == "5,35 * * * *"
    assert snapshot.automation.proactive_review.last_run.health == "idle"
    assert snapshot.sqlite.migrations.status == "current"
    assert snapshot.sqlite.migrations.pending == []
    assert snapshot.sqlite.legacy_imports == []
  end

  test "proactive review inspection exposes bounded latest-job health" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:ok, job} = Oban.insert(ProactiveReviewWorker.new(%{"source" => "cron"}))

    job
    |> Ecto.Changeset.change(
      state: "completed",
      attempt: 1,
      attempted_at: now,
      completed_at: now,
      errors: [%{"attempt" => 1, "at" => DateTime.to_iso8601(now), "error" => "private"}]
    )
    |> Repo.update!()

    health = Inspection.snapshot().automation.proactive_review

    assert health.cron == "5,35 * * * *"
    assert health.queue == "delvetown"
    assert health.max_attempts == 5
    assert health.last_run.health == "healthy"
    assert health.last_run.state == "completed"
    assert health.last_run.job_id == job.id
    assert health.last_run.attempt == 1
    assert health.last_run.error_count == 1
    refute inspect(health) =~ "private"
  end

  test "image drafts expose bounded preview and publication state" do
    bytes = <<0x89, 0x50, 0x4E, 0x47, "preview">>

    assert {:ok, _result} =
             ImageDrafts.stage("image:preview", bytes, %{
               caption: "AgentJido at a workbench.",
               alt_text: "A green robot at a workbench.",
               mime_type: "image/png",
               width: 640,
               height: 480,
               source_metadata: %{source: "local_file", filename: "portrait.png"}
             })

    assert [draft] = Inspection.snapshot(image_limit: 1).image_drafts
    assert draft.draft_key == "image:preview"
    assert draft.validation_state == "valid"
    assert draft.publication_state == "staged"
    assert draft.post_uri == nil
    assert draft.artifact.upload_state == "staged"
    assert draft.artifact.upload_attempt_count == 0
    assert draft.artifact.width == 640
    assert draft.artifact.height == 480
    assert draft.artifact.source == "local_file"
    assert draft.artifact.filename == "portrait.png"

    assert draft.artifact.preview_data_url ==
             "data:image/png;base64,#{Base.encode64(bytes)}"
  end

  test "simulated posts expose only durable draft fields in newest-first order" do
    older = ~U[2026-10-05 11:00:00.000000Z]
    newer = ~U[2026-10-05 12:00:00.000000Z]

    Repo.insert!(%InteractionEvent{
      event_key: "event:simulated-reply",
      kind: "reply",
      actor_did: "did:plc:member",
      record_uri: "at://did:plc:member/town.delve.feed.post/reply",
      occurred_at: older,
      state: "completed",
      payload: %{
        "action" => "reply",
        "cycle_status" => "simulated",
        "intent" => "answer_direct_request",
        "model_reason" => "A direct question",
        "private_model_context" => "must stay hidden",
        "manual_publication" => %{
          "status" => "completed",
          "published_at" => "2026-10-05T12:05:00Z",
          "uri" => "at://did:plc:agent/town.delve.feed.post/published"
        },
        "response_format" => "state_machine_sketch",
        "text" => "Give the failure boundary one owner.",
        "topic" => "OTP"
      },
      terminal_at: older
    })

    Repo.insert!(%InteractionEvent{
      event_key: "event:simulated-welcome",
      kind: "new_member",
      actor_did: "did:plc:new-member",
      occurred_at: newer,
      state: "completed",
      payload: %{
        "action" => "welcome",
        "cycle_status" => "simulated",
        "text" => "Welcome to DelveTown. What are you building?"
      },
      terminal_at: newer
    })

    Repo.insert!(%InteractionEvent{
      event_key: "event:acted-post",
      kind: "timeline",
      occurred_at: newer,
      state: "completed",
      payload: %{
        "action" => "post",
        "cycle_status" => "acted",
        "text" => "This public post is not a simulation."
      },
      terminal_at: newer
    })

    snapshot = Inspection.snapshot(simulated_limit: 2)

    assert [welcome, reply] = snapshot.simulated_posts
    assert welcome.action == "welcome"
    assert welcome.text == "Welcome to DelveTown. What are you building?"
    assert reply.action == "reply"
    assert reply.topic == "OTP"
    assert reply.response_format == "state_machine_sketch"
    assert reply.published_status == "completed"
    assert reply.published_at == "2026-10-05T12:05:00Z"
    assert reply.published_uri == "at://did:plc:agent/town.delve.feed.post/published"
    refute inspect(snapshot.simulated_posts) =~ "must stay hidden"
    refute inspect(snapshot.simulated_posts) =~ "This public post"
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
      [
        ImageDraft,
        ImageArtifact,
        AuditEvent,
        Effect,
        Conversation,
        Actor,
        InteractionEvent,
        ScanState,
        LegacyImport,
        Oban.Job
      ],
      &Repo.delete_all/1
    )
  end
end
