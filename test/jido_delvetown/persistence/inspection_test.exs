defmodule JidoDelvetown.InspectionTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{DraftReviews, ImageDrafts, Inspection, InteractionLedger, Repo}
  alias JidoDelvetown.Workers.ProactiveReviewWorker

  alias JidoDelvetown.Storage.{
    Actor,
    AuditEvent,
    Conversation,
    Effect,
    ImageArtifact,
    DraftReview,
    ImageDraft,
    ImageGenerationRequest,
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
    assert snapshot.events.recent == []
    assert snapshot.simulated_posts == []
    assert snapshot.like_proposals == []
    assert snapshot.image_drafts == []
    assert snapshot.image_generation_requests == []
    assert snapshot.scans == []
    assert snapshot.effects.completed_receipts == []
    assert snapshot.automation.proactive_review.cron == "5,35 * * * *"
    assert snapshot.automation.proactive_review.last_run.health == "idle"
    assert snapshot.sqlite.migrations.status == "current"
    assert snapshot.sqlite.migrations.pending == []
    assert snapshot.sqlite.legacy_imports == []
  end

  test "recent inbox events are bounded and expose only safe operator fields" do
    older = ~U[2026-10-05 11:00:00.000000Z]
    newer = ~U[2026-10-05 12:00:00.000000Z]

    Repo.insert!(%Actor{
      did: "did:plc:member",
      handle: "member.test",
      display_name: "Member",
      first_seen_at: older,
      last_seen_at: newer,
      metadata: %{"private" => "hidden actor note"}
    })

    Repo.insert!(%InteractionEvent{
      event_key: "notification:reply",
      kind: "reply",
      actor_did: "did:plc:member",
      record_uri: "at://did:plc:member/town.delve.feed.post/reply",
      occurred_at: older,
      state: "pending",
      payload: %{
        "action" => "reply",
        "cycle_status" => "proposed",
        "text" => "A bounded reply proposal.",
        "model_reason" => "Direct question",
        "private_model_context" => "must stay hidden"
      },
      inserted_at: older,
      updated_at: older
    })

    Repo.insert!(%InteractionEvent{
      event_key: "notification:like",
      kind: "like",
      actor_did: "did:plc:member",
      record_uri: "at://did:plc:member/town.delve.feed.post/liked",
      occurred_at: newer,
      state: "completed",
      payload: %{},
      terminal_at: newer,
      inserted_at: newer,
      updated_at: newer
    })

    Repo.insert!(%InteractionEvent{
      event_key: "timeline:excluded",
      kind: "timeline",
      occurred_at: newer,
      state: "completed",
      payload: %{"private" => "excluded event"},
      terminal_at: newer,
      inserted_at: newer,
      updated_at: newer
    })

    snapshot = Inspection.snapshot(limit: 2)

    assert [like, reply] = snapshot.events.recent
    assert like.kind == "like"
    assert like.state == "completed"

    assert like.actor == %{
             did: "did:plc:member",
             handle: "member.test",
             display_name: "Member"
           }

    assert like.proposal == nil
    assert reply.kind == "reply"
    assert reply.state == "pending"

    assert reply.proposal == %{
             action: "reply",
             status: "proposed",
             text: "A bounded reply proposal.",
             reason: "Direct question"
           }

    refute inspect(snapshot.events.recent) =~ "must stay hidden"
    refute inspect(snapshot.events.recent) =~ "hidden actor note"
    refute inspect(snapshot.events.recent) =~ "excluded event"
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

    assert {:ok, _review} = DraftReviews.decide("image", "image:preview", "approved")

    assert [draft] = Inspection.snapshot(image_limit: 1).image_drafts
    assert draft.draft_key == "image:preview"
    assert draft.validation_state == "valid"
    assert draft.publication_state == "staged"
    assert draft.review.state == "approved"
    assert is_binary(draft.review.reviewed_at)
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

  test "image generation activity exposes progress, failure, usage, and provenance" do
    now = ~U[2026-10-06 15:00:00.000000Z]
    bytes = <<0x89, 0x50, 0x4E, 0x47, "generated-preview">>

    assert {:ok, staged} =
             ImageDrafts.stage("image:generated", bytes, %{
               caption: "A generated scene.",
               alt_text: "A green robot draws a map.",
               mime_type: "image/png",
               width: 1024,
               height: 1024,
               source_metadata: %{
                 source: "image_generation",
                 generation_request_id: "generation:completed"
               }
             })

    Repo.insert!(%ImageGenerationRequest{
      request_key: "generation:completed",
      request_fingerprint: String.duplicate("a", 64),
      provider: "openai",
      model: "gpt-image-1-mini",
      prompt: "A green robot draws a map.",
      options: %{
        "size" => [1024, 1024],
        "quality" => "medium",
        "output_format" => "png",
        "timeout_ms" => 120_000
      },
      request_metadata: %{
        "settings" => %{"scope" => "active", "schema_version" => 1, "version" => 7}
      },
      state: "completed",
      attempt_count: 1,
      usage: %{"generated_images" => 1, "total_cost" => 0.02, "currency" => "USD"},
      response_metadata: %{
        "provenance" => %{
          "adapter" => "req_llm",
          "response_id" => "response_1",
          "generated_at" => DateTime.to_iso8601(now),
          "request_fingerprint" => String.duplicate("a", 64)
        }
      },
      artifact_digest: staged.artifact.digest,
      reserved_at: now,
      attempted_at: now,
      completed_at: now,
      inserted_at: now,
      updated_at: now
    })

    Repo.insert!(%ImageGenerationRequest{
      request_key: "generation:failed",
      request_fingerprint: String.duplicate("b", 64),
      provider: "openai",
      model: "gpt-image-1-mini",
      prompt: "A failed prompt.",
      options: %{"size" => "auto", "quality" => "low"},
      request_metadata: %{},
      state: "failed",
      attempt_count: 1,
      failure: %{
        "kind" => "provider",
        "message" => "The provider rejected the request.",
        "outcome" => "failed",
        "retryable" => false,
        "details" => %{"secret" => "hidden"}
      },
      reserved_at: now,
      attempted_at: now,
      completed_at: now,
      inserted_at: now,
      updated_at: DateTime.add(now, 1, :second)
    })

    snapshot = Inspection.snapshot(image_limit: 2)
    assert [failed, completed] = snapshot.image_generation_requests
    assert failed.state == "failed"
    assert failed.failure.kind == "provider"
    assert failed.failure.message == "The provider rejected the request."
    refute inspect(failed.failure) =~ "hidden"

    assert completed.size == "1024x1024"
    assert completed.usage["total_cost"] == 0.02
    assert completed.provenance.response_id == "response_1"
    assert completed.settings == %{scope: "active", schema_version: 1, version: 7}

    assert [draft] = snapshot.image_drafts
    assert draft.generation.request_key == "generation:completed"
    assert draft.generation.provenance.adapter == "req_llm"
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
        "settings" => %{"scope" => "active", "schema_version" => 1, "version" => 8},
        "model_reason" => "A direct question",
        "private_model_context" => "must stay hidden",
        "manual_publication" => %{
          "status" => "completed",
          "settings" => %{"scope" => "active", "schema_version" => 1, "version" => 9},
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

    assert {:ok, _review} =
             DraftReviews.decide("text", "event:simulated-welcome", "rejected")

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
    assert welcome.review.state == "rejected"
    assert reply.review == %{state: "pending", reviewed_at: nil}
    assert reply.action == "reply"
    assert reply.topic == "OTP"
    assert reply.response_format == "state_machine_sketch"
    assert reply.published_status == "completed"
    assert reply.published_at == "2026-10-05T12:05:00Z"
    assert reply.published_uri == "at://did:plc:agent/town.delve.feed.post/published"
    assert reply.settings == %{scope: "active", schema_version: 1, version: 8}
    assert reply.publication_settings == %{scope: "active", schema_version: 1, version: 9}
    refute inspect(snapshot.simulated_posts) =~ "must stay hidden"
    refute inspect(snapshot.simulated_posts) =~ "This public post"
  end

  test "like proposals are bounded, deduplicated, and separate from text drafts" do
    insert_like_event("duplicate-proposed", "target-one", "proposed", "pending", "10:00:00")
    insert_like_event("proposed", "target-two", "proposed", "pending", "10:30:00")
    insert_like_event("ignored", "target-three", "skipped", "ignored", "10:45:00")
    insert_like_event("failed", "target-four", "failed", "failed", "10:50:00")
    insert_like_event("duplicate-simulated", "target-one", "simulated", "completed", "11:00:00")

    assert {:ok, _review} =
             DraftReviews.decide("like", "like:duplicate-simulated", "approved")

    snapshot = Inspection.snapshot(simulated_limit: 10)
    proposals = Map.new(snapshot.like_proposals, &{&1.target_uri, &1})

    assert map_size(proposals) == 4
    assert snapshot.simulated_posts == []

    target_one = proposals["at://did:plc:author/town.delve.feed.post/target-one"]
    assert target_one.proposal_status == "simulated"
    assert target_one.publication_state == "simulated"
    assert target_one.review.state == "approved"
    assert target_one.target_author.handle == "author.test"
    assert target_one.post_text == "Which OTP boundary should own this failure?"
    assert target_one.selection_reason == "useful discussion scored 83"
    assert target_one.policy_score == 83
    assert target_one.selected_at == "2026-10-05T11:00:00Z"
    assert target_one.budget == %{date: "2026-10-05", likes: 1, limit: 5, remaining: 4}

    assert proposals["at://did:plc:author/town.delve.feed.post/target-two"].publication_state ==
             "proposed"

    assert proposals["at://did:plc:author/town.delve.feed.post/target-three"].publication_state ==
             "ignored"

    assert proposals["at://did:plc:author/town.delve.feed.post/target-four"].publication_state ==
             "failed"

    refute inspect(snapshot.like_proposals) =~ "hidden model trace"
    refute inspect(snapshot.like_proposals) =~ "private failure detail"

    assert {:ok, _event} =
             InteractionLedger.record_manual_publication("like:duplicate-simulated", %{
               status: "completed",
               published_at: "2026-10-05T11:02:00Z",
               uri: "at://did:plc:bot/town.delve.feed.like/published",
               effect_key: "like:durable",
               settings: %{scope: "active", schema_version: 1, version: 10}
             })

    [published | _rest] = Inspection.snapshot(simulated_limit: 10).like_proposals
    assert published.target_uri == target_one.target_uri
    assert published.publication_state == "published"
    assert published.published_at == "2026-10-05T11:02:00Z"
    assert published.published_uri == "at://did:plc:bot/town.delve.feed.like/published"
    assert published.publication_effect_key == "like:durable"
    assert published.settings == %{scope: "active", schema_version: 1, version: 7}
    assert published.publication_settings == %{scope: "active", schema_version: 1, version: 10}
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
    assert receipt.settings == %{scope: "active", schema_version: 1, version: 6}
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
      settings: %{"scope" => "active", "schema_version" => 1, "version" => 6},
      receipt: receipt,
      reserved_at: now,
      completed_at: if(status in ["completed", "permanent_failure"], do: now)
    }
  end

  defp insert_like_event(suffix, target, cycle_status, state, time) do
    selected_at = "2026-10-05T#{time}Z"
    occurred_at = DateTime.from_iso8601("2026-10-05T#{time}.000000Z") |> elem(1)

    Repo.insert!(%InteractionEvent{
      event_key: "like:#{suffix}",
      kind: "proactive",
      actor_did: "did:plc:author",
      record_uri: "at://did:plc:author/town.delve.feed.post/#{target}",
      occurred_at: occurred_at,
      state: state,
      failure: if(state == "failed", do: %{"reason" => "private failure detail"}),
      terminal_at: if(state in ["completed", "ignored", "failed"], do: occurred_at),
      payload: %{
        "action" => "like",
        "cycle_status" => cycle_status,
        "settings" => %{"scope" => "active", "schema_version" => 1, "version" => 7},
        "private_model_context" => "hidden model trace",
        "selection" => %{"reason" => "useful discussion scored 83", "score" => 83},
        "like_review" => %{
          "author" => %{
            "did" => "did:plc:author",
            "handle" => "author.test",
            "display_name" => "Author"
          },
          "post_text" => "Which OTP boundary should own this failure?",
          "selected_at" => selected_at,
          "budget" => %{"date" => "2026-10-05", "likes" => 1, "limit" => 5, "remaining" => 4}
        }
      }
    })
  end

  defp clear_inspection_tables do
    Enum.each(
      [
        DraftReview,
        ImageDraft,
        ImageGenerationRequest,
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
