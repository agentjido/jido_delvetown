defmodule JidoDelvetownWeb.DashboardSnapshotTest do
  use ExUnit.Case, async: true

  alias JidoDelvetownWeb.DashboardSnapshot

  defmodule HealthyDataSource do
    def status do
      %{
        writes_enabled?: false,
        dry_run_mark_actioned?: true,
        budget: %{replies: 2},
        decision: %{action: "reply"},
        last_cycle: %{status: "simulated"},
        last_run: %{summary: "One reply simulated"}
      }
    end

    def recent_events(12) do
      %{workflow: [%{type: "cycle.simulated"}], agent: [%{type: "agent.updated"}]}
    end

    def inspect_state(limit: 6), do: %{events: %{limit: 6}}
  end

  defmodule HealthyPersonality do
    def character do
      %{
        name: "AgentJido",
        personality: %{traits: ["calm", "exact"]},
        extensions: %{
          delvetown: %{
            mission: "Make BEAM agent engineering easier to understand.",
            topical_scope: ["BEAM and OTP"]
          }
        }
      }
    end

    def disclosure, do: %{processing: "Automated processing is disclosed."}
  end

  defmodule HealthyReviews do
    def reactive_review_status, do: %{status: :idle, disabled?: false}
    def proactive_review_status, do: %{status: :queued, disabled?: true}
  end

  defmodule HealthyConfig do
    def manual_publish_enabled?, do: true
    def dashboard_port, do: 4041
  end

  defmodule HealthyConsoleSettings do
    def theme, do: {:ok, "dark"}
  end

  defmodule UnavailableDependency do
    def status, do: {:error, :agent_not_running}
    def recent_events(_limit), do: exit(:event_store_unavailable)
    def inspect_state(_opts), do: raise("database unavailable")
    def character, do: raise("character unavailable")
    def disclosure, do: exit(:disclosure_unavailable)
    def reactive_review_status, do: exit(:reactive_unavailable)
    def proactive_review_status, do: raise("proactive unavailable")
    def manual_publish_enabled?, do: raise("config unavailable")
    def dashboard_port, do: exit(:config_unavailable)
  end

  test "assembles the healthy dashboard display snapshot" do
    snapshot =
      DashboardSnapshot.load(
        data_source: HealthyDataSource,
        personality: HealthyPersonality,
        review_controller: HealthyReviews,
        config: HealthyConfig,
        console_settings: HealthyConsoleSettings,
        now: ~U[2026-10-06 12:34:56.789Z]
      )

    assert snapshot.page_title == "AgentJido / DelveTown"
    assert snapshot.status_error == nil
    assert snapshot.inspection_error == nil
    assert snapshot.operational_state.key == "safe"
    assert snapshot.operational_state.label == "Dry run: actions simulated"
    assert snapshot.budget == %{replies: 2}
    assert snapshot.decision == %{action: "reply"}
    assert snapshot.last_cycle == %{status: "simulated"}
    assert snapshot.last_run == %{summary: "One reply simulated"}
    assert snapshot.workflow_events == [%{type: "cycle.simulated"}]
    assert snapshot.agent_events == [%{type: "agent.updated"}]
    assert snapshot.inspection == %{events: %{limit: 6}}

    assert snapshot.character == %{
             name: "AgentJido",
             mission: "Make BEAM agent engineering easier to understand.",
             traits: ["calm", "exact"],
             topical_scope: ["BEAM and OTP"]
           }

    assert snapshot.disclosure == %{processing: "Automated processing is disclosed."}
    assert snapshot.reactive_review == %{status: :idle, disabled?: false}
    assert snapshot.proactive_review == %{status: :queued, disabled?: true}
    assert snapshot.theme == "dark"
    assert snapshot.manual_publish_enabled
    assert snapshot.port == 4041
    assert snapshot.refreshed_at == "2026-10-06T12:34:56Z"
    assert snapshot.refreshed_label == "12:34:56 UTC"
  end

  test "returns safe display assignments when dependencies are unavailable" do
    snapshot =
      DashboardSnapshot.load(
        data_source: UnavailableDependency,
        personality: UnavailableDependency,
        review_controller: UnavailableDependency,
        config: UnavailableDependency,
        console_settings: UnavailableDependency,
        now: ~U[2026-10-06 12:34:56Z]
      )

    assert snapshot.status == %{}
    assert snapshot.status_error == ":agent_not_running"
    assert snapshot.operational_state.key == "attention"
    assert snapshot.budget == %{}
    assert snapshot.decision == %{}
    assert snapshot.last_cycle == %{}
    assert snapshot.last_run == %{}
    assert snapshot.workflow_events == []
    assert snapshot.agent_events == []
    assert snapshot.inspection == %{}
    assert snapshot.inspection_error =~ "database unavailable"
    assert snapshot.character.name == "AgentJido"
    assert snapshot.character.traits == []
    assert snapshot.disclosure == %{}
    assert snapshot.reactive_review.status == :failed
    assert snapshot.reactive_review.disabled?
    assert snapshot.proactive_review.status == :failed
    assert snapshot.proactive_review.disabled?
    assert snapshot.theme == "system"
    refute snapshot.manual_publish_enabled
    assert snapshot.port == 4040
  end
end
