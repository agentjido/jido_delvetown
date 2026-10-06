defmodule JidoDelvetownWeb.DashboardComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias JidoDelvetownWeb.DashboardComponents

  test "exports one stateless component for each dashboard area" do
    Code.ensure_loaded!(DashboardComponents)

    components = [
      :styles,
      :sidebar_navigation,
      :mobile_navigation,
      :first_run_setup,
      :operational_state,
      :overview,
      :inbox,
      :runtime_health,
      :memory_and_effects,
      :scan_and_database_status,
      :recent_events,
      :planned_controls,
      :agent_information,
      :simulated_actions,
      :footer
    ]

    assert Enum.all?(components, &function_exported?(DashboardComponents, &1, 1))
  end

  test "planned controls keep the proactive LiveView event binding" do
    review = %{
      status: :idle,
      label: "Ready for review",
      detail: "Queue one review with the current dry-run settings.",
      disabled?: false
    }

    html =
      render_component(&DashboardComponents.planned_controls/1, %{
        active_tab: "overview",
        reactive_review: review,
        proactive_review: review
      })

    assert html =~ ~s(aria-label="Manual controls")
    assert html =~ ~s(phx-click="run_proactive_review")
    refute html =~ ~s(phx-click="run_reactive_review")
    refute html =~ "Interaction memory"
  end

  test "inbox owns the manual reactive review control and event state" do
    review = %{
      status: :idle,
      label: "Ready for review",
      detail: "Queue one review with the current dry-run settings.",
      disabled?: false
    }

    html =
      render_component(&DashboardComponents.inbox/1, %{
        active_tab: "inbox",
        reactive_review: review,
        inbox: %{
          actionable_count: 1,
          proposal_count: 1,
          categories: [
            %{key: "reply", label: "Replies", count: 1},
            %{key: "mention", label: "Mentions", count: 0},
            %{key: "follow", label: "Follows", count: 0},
            %{key: "like", label: "Likes", count: 0}
          ],
          last_scan: %{last_completed_at: "2026-10-06T12:00:00Z", lease_active?: false},
          events: [
            %{
              event_key: "reply:1",
              kind: "reply",
              state: "pending",
              actor: %{handle: "member.test"},
              record_uri: "at://did:plc:member/town.delve.feed.post/source",
              occurred_at: "2026-10-06T12:00:00Z",
              proposal: %{
                action: "reply",
                status: "proposed",
                text: "A bounded reply.",
                reason: "Direct question"
              }
            }
          ]
        }
      })

    assert html =~ ~s(id="inbox-panel")
    assert html =~ ~s(phx-click="run_reactive_review")
    assert html =~ "Scan DelveTown now"
    assert html =~ "@member.test"
    assert html =~ "1 proposal"
    assert html =~ "A bounded reply."
    assert html =~ "Direct question"
  end

  test "simulated actions keep publish confirmation local to their component" do
    html =
      render_component(&DashboardComponents.simulated_actions/1, %{
        active_tab: "simulated-posts",
        inspection: %{
          like_proposals: [],
          simulated_posts: [
            %{
              event_key: "event:test-reply",
              action: "reply",
              text: "A supervisor gives this failure boundary one owner.",
              publication_state: "simulated"
            }
          ],
          image_drafts: []
        },
        manual_publish_enabled: true,
        publish_notice: nil,
        like_publish_notice: nil,
        image_publish_notice: nil,
        status: %{}
      })

    assert html =~ ~s(id="simulated-posts-panel")
    assert html =~ ~s(phx-click="publish_simulated")
    assert html =~ ~s(phx-value-event_key="event:test-reply")
    assert html =~ ~s(data-confirm="Publish this exact draft to DelveTown?")
    refute html =~ "Manual controls"
  end
end
