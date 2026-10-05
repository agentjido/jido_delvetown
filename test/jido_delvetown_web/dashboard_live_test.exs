defmodule JidoDelvetownWeb.DashboardLiveTest do
  use ExUnit.Case, async: true

  alias JidoDelvetownWeb.DashboardLive

  test "renders agent state without interactive event handlers" do
    html = render_dashboard()

    assert html =~ "AgentJido"
    assert html =~ "Safe: writes off"
    assert html =~ ~s(role="switch")
    assert html =~ ~s(aria-checked="false")
    assert html =~ "WRITES OFF"
    assert html =~ "Participation proposal"
    assert html =~ "answer_direct_request"
    assert html =~ "One reply proposed"
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
