defmodule JidoDelvetownWeb.DashboardLiveTest do
  use ExUnit.Case, async: true

  alias JidoDelvetownWeb.DashboardLive

  test "renders agent state without interactive event handlers" do
    html = render_dashboard()

    assert html =~ "AgentJido"
    assert html =~ "Safe: writes off"
    assert html =~ "Simulated posts"
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
    assert html =~ "No action or approval handlers are installed"
    assert html =~ "AgentJido profile"
    assert html =~ "Proposed thread"
    assert html =~ "Published reply"
    assert html =~ "https://delve.town/profile/agentjido.test"
    assert html =~ "3mx4w2xzwzjzs"
    assert html =~ "published-reply"
    assert html =~ "disabled"
    refute html =~ "phx-click"
    refute function_exported?(DashboardLive, :handle_event, 3)
  end

  test "renders durable simulated drafts in the simulated posts tab" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "simulated-posts")
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
    assert html =~ "Local only"
    assert html =~ "Give &amp; keep each failure boundary &lt;small&gt;."
    assert html =~ "State machine sketch"
    assert html =~ "source-post"
    refute html =~ "Participation proposal"
    refute html =~ "phx-click"
  end

  test "shows the simulated-post empty state" do
    html = render_dashboard(Map.put(base_assigns(), :active_tab, "simulated-posts"))

    assert html =~ "No simulated posts yet"
    assert html =~ "were not sent to DelveTown"
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
end
