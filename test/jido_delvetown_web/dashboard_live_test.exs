defmodule JidoDelvetownWeb.DashboardLiveTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.SelfPortraitDraft
  alias JidoDelvetownWeb.DashboardLive

  defmodule FakeReviewController do
    def enqueue_reactive_review do
      Application.fetch_env!(:jido_delvetown, :reactive_review_test_result)
    end

    def reactive_review_status do
      Application.fetch_env!(:jido_delvetown, :reactive_review_test_status)
    end
  end

  setup do
    old_controller = Application.get_env(:jido_delvetown, :reactive_review_controller)
    old_result = Application.get_env(:jido_delvetown, :reactive_review_test_result)
    old_status = Application.get_env(:jido_delvetown, :reactive_review_test_status)

    Application.put_env(:jido_delvetown, :reactive_review_controller, FakeReviewController)

    Application.put_env(
      :jido_delvetown,
      :reactive_review_test_result,
      {:ok, review_feedback(:queued)}
    )

    Application.put_env(
      :jido_delvetown,
      :reactive_review_test_status,
      review_feedback(:idle)
    )

    on_exit(fn ->
      restore_env(:reactive_review_controller, old_controller)
      restore_env(:reactive_review_test_result, old_result)
      restore_env(:reactive_review_test_status, old_status)
    end)

    :ok
  end

  test "renders agent state with the manual reactive review control" do
    html = render_dashboard()

    assert html =~ "AgentJido"
    assert html =~ "Safe: writes off"
    assert html =~ "Simulated posts"
    assert html =~ "Image drafts"
    assert html =~ ~s(id="overview-tab")
    assert html =~ ~s(aria-selected="true")
    assert html =~ ~s(role="switch")
    assert html =~ ~s(aria-checked="false")
    assert html =~ "WRITES OFF"
    assert html =~ "Participation proposal"
    assert html =~ "answer_direct_request"
    assert html =~ "One reply proposed"
    assert html =~ "Policy score"
    assert html =~ "direct scored 138"
    assert html =~ "Interaction memory"
    assert html =~ "Recent actor contact"
    assert html =~ "member.test"
    assert html =~ "Effect health"
    assert html =~ "Uncertain"
    assert html =~ "at://receipt"
    assert html =~ "Scan watermarks"
    assert html =~ "notifications"
    assert html =~ "SQLite status"
    assert html =~ "3 migrations applied"
    assert html =~ "dets-and-file-v1"
    assert html =~ "Run reactive review"
    assert html =~ "Approve human-in-the-loop post"
    assert html =~ "Ready for review"
    assert html =~ "current dry-run settings"
    assert html =~ ~s(id="run-reactive-review")
    assert html =~ ~s(phx-click="run_reactive_review")
    assert html =~ "AgentJido profile"
    assert html =~ "Proposed thread"
    assert html =~ "Published reply"
    assert html =~ "https://delve.town/profile/agentjido.test"
    assert html =~ "3mx4w2xzwzjzs"
    assert html =~ "published-reply"
    assert html =~ "disabled"
    assert function_exported?(DashboardLive, :handle_event, 3)
  end

  test "reports queued, duplicate, unavailable, and worker-failure review results" do
    cases = [
      {{:ok, review_feedback(:queued)}, "queued", "Review queued"},
      {{:ok, review_feedback(:skipped)}, "skipped", "Review already queued"},
      {{:error, :runtime_unavailable}, "failed", "Runtime unavailable"},
      {{:ok, review_feedback(:failed)}, "failed", "Review failed"}
    ]

    for {result, status, label} <- cases do
      Application.put_env(:jido_delvetown, :reactive_review_test_result, result)

      socket =
        %Phoenix.LiveView.Socket{}
        |> Phoenix.Component.assign(base_assigns())

      assert {:noreply, updated_socket} =
               DashboardLive.handle_event("run_reactive_review", %{}, socket)

      assert updated_socket.assigns.reactive_review.status == String.to_existing_atom(status)

      html = render_dashboard(updated_socket.assigns)
      assert html =~ ~s(data-status="#{status}")
      assert html =~ label
    end
  end

  test "renders durable simulated drafts in the simulated posts tab" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "simulated-posts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :simulated_posts], [
        %{
          event_key: "event:simulated-reply",
          action: "reply",
          text: "Give & keep each failure boundary <small>.",
          topic: "OTP",
          reason: "A direct technical question",
          response_format: "state_machine_sketch",
          intent: "answer_direct_request",
          record_uri: "at://did:plc:member/town.delve.feed.post/source-post",
          simulated_at: "2026-10-05T12:04:00Z"
        }
      ])

    html = render_dashboard(assigns)

    assert html =~ ~s(id="simulated-posts-panel")
    assert html =~ "SQLite dry-run history"
    assert html =~ "Manual publish ready"
    assert html =~ "Give &amp; keep each failure boundary &lt;small&gt;."
    assert html =~ "State machine sketch"
    assert html =~ "source-post"
    assert html =~ "Manual publish ready"
    assert html =~ "Publish to DelveTown"
    assert html =~ ~s(phx-click="publish_simulated")
    assert html =~ ~s(phx-value-event_key="event:simulated-reply")
    refute html =~ "phx-value-event-key"
    refute html =~ ~s(disabled="")
    refute html =~ "Participation proposal"
  end

  test "replaces the publish button with the saved publication link" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "simulated-posts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :simulated_posts], [
        %{
          event_key: "event:published-reply",
          action: "reply",
          text: "This draft is now public.",
          published_status: "completed",
          published_uri: "at://did:plc:agentjido/town.delve.feed.post/published-rkey"
        }
      ])

    html = render_dashboard(assigns)

    assert html =~ "Published"
    assert html =~ "View published post"
    assert html =~ "/profile/agentjido.test/post/published-rkey"
    refute html =~ "Publish to DelveTown"
  end

  test "shows the simulated-post empty state" do
    html = render_dashboard(Map.put(base_assigns(), :active_tab, "simulated-posts"))

    assert html =~ "No simulated posts yet"
    assert html =~ "were not sent to DelveTown"
  end

  test "shows local image previews and a confirmed manual publish action" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "image-drafts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :image_drafts], [
        %{
          draft_key: "agentjido:self-portrait",
          caption: "AgentJido at the workbench.",
          alt_text: "A green robot writing at a workbench.",
          validation_state: "valid",
          publication_state: "staged",
          inserted_at: "2026-10-05T12:04:00Z",
          post_uri: nil,
          artifact: %{
            digest: "sha256:preview",
            preview_data_url: "data:image/png;base64,iVBORw0KGgo=",
            mime_type: "image/png",
            byte_size: 8,
            width: 1024,
            height: 1024,
            upload_state: "staged"
          }
        }
      ])

    html = render_dashboard(assigns)

    assert html =~ ~s(id="image-drafts-panel")
    assert html =~ "Staging and review are local"
    assert html =~ ~s(src="data:image/png;base64,iVBORw0KGgo=")
    assert html =~ ~s(alt="A green robot writing at a workbench.")
    assert html =~ "AgentJido at the workbench."
    assert html =~ "Validation"
    assert html =~ "Upload"
    assert html =~ "Publication"
    assert html =~ "1024×1024"
    assert html =~ ~s(phx-click="publish_image")
    assert html =~ ~s(phx-value-draft_key="agentjido:self-portrait")
    assert html =~ "Upload this image and publish this exact draft"
  end

  test "shows a published image link instead of the publish button" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "image-drafts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :image_drafts], [
        %{
          draft_key: "image:published",
          caption: "Published image.",
          alt_text: "Published image preview.",
          validation_state: "valid",
          publication_state: "published",
          post_uri: "at://did:plc:agentjido/town.delve.feed.post/image-rkey",
          artifact: %{
            digest: "sha256:published",
            preview_data_url: "data:image/png;base64,iVBORw0KGgo=",
            mime_type: "image/png",
            byte_size: 8,
            width: nil,
            height: nil,
            upload_state: "uploaded"
          }
        }
      ])

    html = render_dashboard(assigns)

    assert html =~ "Published"
    assert html =~ "/profile/agentjido.test/post/image-rkey"
    refute html =~ "Publish image to DelveTown"
  end

  test "renders the fixed AgentJido self-portrait as its exact top-level draft" do
    definition = SelfPortraitDraft.definition()
    bytes = File.read!(definition.asset_path)
    preview_data_url = "data:image/png;base64,#{Base.encode64(bytes)}"

    assigns =
      base_assigns()
      |> Map.put(:active_tab, "image-drafts")
      |> put_in([:inspection, :image_drafts], [
        %{
          draft_key: definition.draft_key,
          caption: definition.caption,
          alt_text: definition.alt_text,
          validation_state: "valid",
          publication_state: "staged",
          artifact: %{
            digest: definition.expected_digest,
            preview_data_url: preview_data_url,
            mime_type: definition.mime_type,
            byte_size: byte_size(bytes),
            width: definition.width,
            height: definition.height,
            upload_state: "staged"
          }
        }
      ])

    html = render_dashboard(assigns)

    assert html =~ definition.draft_key
    assert html =~ definition.caption
    assert html =~ definition.alt_text
    assert html =~ definition.expected_digest
    assert html =~ "1024×1024"
    assert html =~ "data:image/png;base64,"
    assert html =~ "Top-level image"
    assert html =~ "Publish image to DelveTown"
  end

  test "shows when protocol writes are enabled" do
    assigns =
      base_assigns()
      |> put_in([:status, :writes_enabled?], true)
      |> Map.put(:operational_state, %{
        key: "active",
        label: "Writes enabled",
        effect: "Scheduled Agent work can create public protocol effects.",
        next: "Use the review path before any future one-click action."
      })

    html = render_dashboard(assigns)

    assert html =~ "Writes enabled"
    assert html =~ ~s(aria-checked="true")
    assert html =~ "WRITES ON"
  end

  test "shows when dry-run actions advance local memory" do
    assigns =
      base_assigns()
      |> put_in([:status, :dry_run_mark_actioned?], true)
      |> Map.put(:operational_state, %{
        key: "safe",
        label: "Dry run: actions simulated",
        effect: "Protocol effects are blocked. Selected actions advance local dry-run memory.",
        next: "A simulated action is not published and will not run again."
      })

    html = render_dashboard(assigns)

    assert html =~ "Dry run: actions simulated"
    assert html =~ "Selected actions advance local dry-run memory"
    assert html =~ "A simulated action is not published"
    assert html =~ "WRITES OFF"
  end

  test "links the latest published reply from the audit event" do
    assigns =
      base_assigns()
      |> update_in([:last_run], &Map.delete(&1, :record_uri))
      |> Map.put(:workflow_events, [
        %{
          type: :published_reply,
          at: "2026-10-05T14:05:13Z",
          data: %{
            record_uri: "at://did:plc:agentjido/town.delve.feed.post/audited-reply"
          }
        }
      ])

    html = render_dashboard(assigns)

    assert html =~ "Published reply"
    assert html =~ "audited-reply"
  end

  defp render_dashboard(assigns \\ base_assigns()) do
    assigns
    |> DashboardLive.render()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp base_assigns do
    %{
      active_tab: "overview",
      status: %{
        writes_enabled?: false,
        schedule_enabled?: true,
        cron: "*/15 * * * *",
        session: %{connected?: true, handle: "agentjido.test"}
      },
      status_error: nil,
      budget: %{replies: 1, posts: 0},
      decision: %{
        action: "reply",
        reason: "The thread asks a direct technical question.",
        topic: "OTP",
        text: "A supervisor gives this failure boundary one owner."
      },
      last_cycle: %{
        intent: "answer_direct_request",
        kind: "reactive",
        status: "proposed",
        candidate_id: "at://did:plc:a5uoyxqts4y3iwo2dk74ygma/town.delve.feed.post/3mx4w2xzwzjzs"
      },
      last_run: %{
        summary: "One reply proposed",
        selection: %{score: 138, reason: "direct scored 138"},
        record_uri: "at://did:plc:agentjido/town.delve.feed.post/published-reply"
      },
      workflow_events: [
        %{
          type: "cycle.proposed",
          at: "2026-10-05T12:00:00Z",
          data: %{action: "reply", record_uri: nil}
        }
      ],
      agent_events: [],
      inspection: %{
        simulated_posts: [],
        image_drafts: [],
        events: %{
          counts: %{
            "pending" => 1,
            "claimed" => 0,
            "completed" => 4,
            "ignored" => 2,
            "failed" => 0
          }
        },
        actors: %{
          recent: [
            %{
              did: "did:plc:member",
              handle: "member.test",
              display_name: "Member",
              last_interaction_at: "2026-10-05T11:58:00Z",
              contact_count: 2,
              welcome_status: "completed",
              opted_out?: false
            }
          ]
        },
        conversations: %{counts: %{"active" => 1, "closed" => 0}},
        scans: [
          %{
            name: "notifications",
            cursor: "cursor-2",
            lease_active?: false,
            last_completed_at: "2026-10-05T11:59:00Z"
          }
        ],
        effects: %{
          counts: %{
            "reserved" => 0,
            "uncertain" => 1,
            "completed" => 3,
            "permanent_failure" => 0
          },
          reconciled: 1,
          attention: [
            %{
              operation_key: "reply:pending",
              kind: "reply",
              status: "uncertain",
              attempt_count: 1
            }
          ],
          completed_receipts: [
            %{
              operation_key: "reply:complete",
              rkey: "reply-rkey",
              completed_at: "2026-10-05T11:57:00Z",
              receipt: %{uri: "at://receipt", cid: "bafy"}
            }
          ]
        },
        sqlite: %{
          migrations: %{
            status: "current",
            applied: ["20261005000000", "20261005000001", "20261005000002"],
            pending: []
          },
          legacy_imports: [
            %{
              name: "dets-and-file-v1",
              status: "complete",
              counts: %{"effects" => 3, "events" => 2, "checkpoints" => 1}
            }
          ]
        }
      },
      inspection_error: nil,
      reactive_review: review_feedback(:idle),
      manual_publish_enabled: false,
      publish_notice: nil,
      image_publish_notice: nil,
      character: %{
        name: "AgentJido",
        mission: "Make BEAM agent engineering easier to understand.",
        traits: ["calm", "exact"],
        topical_scope: ["BEAM and OTP", "agent architecture"]
      },
      disclosure: %{operator: %{contact: "https://mike-hostetler.com"}},
      port: 4040,
      refreshed_at: "2026-10-05T12:00:00Z",
      refreshed_label: "12:00:00 UTC",
      operational_state: %{
        key: "safe",
        label: "Safe: writes off",
        effect: "Protocol effects are blocked. Review cycles can inspect and propose.",
        next: nil
      }
    }
  end

  defp review_feedback(:idle) do
    %{
      status: :idle,
      label: "Ready for review",
      detail: "Queue one review with the current dry-run settings.",
      disabled?: false,
      job_id: nil
    }
  end

  defp review_feedback(:queued) do
    %{
      status: :queued,
      label: "Review queued",
      detail: "The review will run through the normal scan lease.",
      disabled?: true,
      job_id: 11
    }
  end

  defp review_feedback(:skipped) do
    %{
      status: :skipped,
      label: "Review already queued",
      detail: "No duplicate job was created.",
      disabled?: true,
      job_id: 11
    }
  end

  defp review_feedback(:failed) do
    %{
      status: :failed,
      label: "Review failed",
      detail: "The worker failed and Oban will retry it.",
      disabled?: true,
      job_id: 11
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_delvetown, key)
  defp restore_env(key, value), do: Application.put_env(:jido_delvetown, key, value)
end
