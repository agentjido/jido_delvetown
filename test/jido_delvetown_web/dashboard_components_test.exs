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
      :drafts,
      :people,
      :settings,
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

  test "drafts keep approval and publish controls local to their component" do
    html =
      render_component(&DashboardComponents.drafts/1, %{
        active_tab: "drafts",
        drafts: %{
          pending_count: 0,
          approved_count: 1,
          rejected_count: 0,
          published_count: 0,
          type_counts: %{text: 1, like: 0, image: 0}
        },
        inspection: %{
          like_proposals: [],
          simulated_posts: [
            %{
              event_key: "event:test-reply",
              action: "reply",
              text: "A supervisor gives this failure boundary one owner.",
              publication_state: "simulated",
              review: %{state: "approved"}
            }
          ],
          image_drafts: []
        },
        manual_publish_enabled: true,
        publish_notice: nil,
        like_publish_notice: nil,
        image_publish_notice: nil,
        draft_review_notice: nil,
        status: %{}
      })

    assert html =~ ~s(id="drafts-panel")
    assert html =~ ~s(phx-click="review_draft")
    assert html =~ ~s(phx-value-decision="rejected")
    assert html =~ ~s(phx-click="publish_simulated")
    assert html =~ ~s(phx-value-event_key="event:test-reply")
    assert html =~ ~s(data-confirm="Publish this exact approved draft to DelveTown?")
    refute html =~ "Manual controls"
  end

  test "a pending draft cannot show a publish action" do
    html =
      render_component(&DashboardComponents.drafts/1, %{
        active_tab: "drafts",
        drafts: %{
          pending_count: 1,
          approved_count: 0,
          rejected_count: 0,
          published_count: 0,
          type_counts: %{text: 1, like: 0, image: 0}
        },
        inspection: %{
          like_proposals: [],
          simulated_posts: [
            %{
              event_key: "event:pending-reply",
              action: "reply",
              text: "A local draft.",
              review: %{state: "pending"}
            }
          ],
          image_drafts: []
        },
        manual_publish_enabled: true,
        publish_notice: nil,
        like_publish_notice: nil,
        image_publish_notice: nil,
        draft_review_notice: nil,
        status: %{}
      })

    assert html =~ ~s(phx-value-decision="approved")
    assert html =~ ~s(phx-value-decision="rejected")
    refute html =~ ~s(phx-click="publish_simulated")
  end

  test "people shows relationship memory, topics, recent contact, and exclusions" do
    html =
      render_component(&DashboardComponents.people/1, %{
        active_tab: "people",
        people: %{
          counts: %{
            known: 2,
            friends: 1,
            followers: 2,
            following: 1,
            mutuals: 1,
            excluded: 1
          },
          visible_count: 2,
          truncated?: false,
          records: [
            %{
              did: "did:plc:friend",
              handle: "friend.test",
              display_name: "BEAM Friend",
              friend?: true,
              follows_agent: "yes",
              agent_follows: "yes",
              topics: ["BEAM", "OTP"],
              notes: "Ask about supervision trees.",
              contact_count: 3,
              welcome_status: "completed",
              reference_count: 2,
              last_interaction_at: "2026-10-06T12:00:00Z",
              friend_since: "2026-10-01T12:00:00Z",
              last_referenced_at: "2026-10-05T12:00:00Z",
              opted_out?: false,
              do_not_mention?: false
            },
            %{
              did: "did:plc:excluded",
              handle: "excluded.test",
              friend?: false,
              follows_agent: "yes",
              agent_follows: "no",
              topics: [],
              contact_count: 0,
              reference_count: 0,
              opted_out?: true,
              do_not_mention?: true
            }
          ]
        }
      })

    assert html =~ ~s(id="people-panel")
    assert html =~ "People and participation boundaries"
    assert html =~ "BEAM Friend"
    assert html =~ "@friend.test"
    assert html =~ "Mutual follow"
    assert html =~ ">BEAM</span>"
    assert html =~ ">OTP</span>"
    assert html =~ "Ask about supervision trees."
    assert html =~ "Oct 06 · 12:00 UTC"
    assert html =~ "Participation excluded:"
    assert html =~ "Actor opted out"
    assert html =~ "Do not mention"
    assert html =~ "https://delve.town/profile/friend.test"
    refute html =~ "phx-click"
  end
end
