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

  test "planned controls keep their LiveView event bindings" do
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
    assert html =~ ~s(phx-click="run_reactive_review")
    assert html =~ ~s(phx-click="run_proactive_review")
    refute html =~ "Interaction memory"
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
