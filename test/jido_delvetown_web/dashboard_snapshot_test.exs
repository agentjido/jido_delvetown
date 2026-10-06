defmodule JidoDelvetownWeb.DashboardSnapshotTest do
  use ExUnit.Case, async: true

  alias JidoDelvetownWeb.DashboardSnapshot

  defmodule HealthyDataSource do
    def status do
      %{
        autonomy_mode: "observe",
        credentials_configured?: true,
        session: %{connected?: true, handle: "agentjido.test"},
        schedule_enabled?: true,
        cron: "*/15 * * * *",
        proactive_review_cron: "5,35 * * * *",
        member_discovery_cron: "7 * * * *",
        friend_sync_cron: "17 * * * *",
        writes_enabled?: false,
        dry_run_mark_actioned?: true,
        budget: %{replies: 2, posts: 0, welcomes: 1, follows: 0, likes: 2},
        decision: %{action: "reply"},
        last_cycle: %{status: "simulated"},
        last_run: %{summary: "One reply simulated"}
      }
    end

    def recent_events(12) do
      %{
        workflow: [
          %{
            type: :decision,
            at: "2026-10-06T12:30:00Z",
            data: %{action: "reply", cycle_status: "simulated", model_reason: "Direct question"}
          }
        ],
        agent: [%{type: "agent.updated"}]
      }
    end

    def inspect_state(limit: 6) do
      %{
        events: %{
          limit: 6,
          counts: %{"pending" => 0, "failed" => 0},
          recent: [
            %{
              event_key: "reply:1",
              kind: "reply",
              state: "completed",
              proposal: nil
            }
          ]
        },
        people: %{
          counts: %{
            known: 1,
            friends: 1,
            followers: 1,
            following: 1,
            mutuals: 1,
            excluded: 0
          },
          records: [%{did: "did:plc:member", handle: "member.test", friend?: true}],
          visible_count: 1,
          truncated?: false
        },
        effects: %{attention: []},
        sqlite: %{migrations: %{status: "current"}}
      }
    end
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

  defmodule HealthyBehaviorSettings do
    def manual_publish_enabled?, do: true
  end

  defmodule HealthyConnectionSettings do
    def dashboard, do: {:ok, %{enabled?: true, port: 4041}}
  end

  defmodule HealthyConsoleSettings do
    def theme, do: {:ok, "dark"}
  end

  defmodule HealthyLimitsSettings do
    def current do
      {:ok,
       %{
         daily_reply_limit: 3,
         daily_post_limit: 1,
         daily_welcome_limit: 2,
         daily_follow_limit: 5,
         daily_like_limit: 5
       }}
    end
  end

  defmodule HealthyImageGenerationSettings do
    def current do
      {:ok,
       %{
         enabled?: true,
         provider: "openai",
         model: "gpt-image-1-mini",
         size: {1024, 1024},
         quality: "medium",
         output_format: :png,
         timeout_ms: 120_000,
         daily_limit: 2,
         allowed_modes: ["manual"],
         budget: %{used: 1, limit: 2, remaining: 1},
         settings: %{scope: "active", schema_version: 1, version: 4}
       }}
    end
  end

  defmodule HealthySetup do
    def status do
      {:ok,
       %{
         required?: true,
         identifier: "",
         password_configured?: false,
         decision_model: "openai:gpt-4o-mini",
         model_options: [],
         autonomy_mode: "observe",
         autonomy_options: [],
         llm_key: %{environment: "OPENAI_API_KEY", configured?: true},
         settings_version: 1
       }}
    end
  end

  defmodule HealthySettingsEditor do
    def load do
      {:ok,
       %{
         available?: true,
         version: 4,
         schema_version: 2,
         sections: [%{key: "behavior", fields: []}],
         history: [%{version: 4, current?: true}],
         activation_guide: []
       }}
    end
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
    def dashboard, do: exit(:config_unavailable)
    def current, do: {:error, :settings_unavailable}
    def load, do: {:error, :settings_editor_unavailable}
  end

  test "assembles the healthy dashboard display snapshot" do
    snapshot =
      DashboardSnapshot.load(
        data_source: HealthyDataSource,
        personality: HealthyPersonality,
        review_controller: HealthyReviews,
        behavior_settings: HealthyBehaviorSettings,
        connection_settings: HealthyConnectionSettings,
        console_settings: HealthyConsoleSettings,
        limits_settings: HealthyLimitsSettings,
        image_generation_settings: HealthyImageGenerationSettings,
        setup_service: HealthySetup,
        settings_editor: HealthySettingsEditor,
        now: ~U[2026-10-06 12:34:56.789Z]
      )

    assert snapshot.page_title == "AgentJido / DelveTown"
    assert snapshot.status_error == nil
    assert snapshot.inspection_error == nil
    assert snapshot.operational_state.key == "safe"
    assert snapshot.operational_state.label == "Dry run: actions simulated"
    assert snapshot.budget == %{replies: 2, posts: 0, welcomes: 1, follows: 0, likes: 2}
    assert snapshot.decision == %{action: "reply"}
    assert snapshot.last_cycle == %{status: "simulated"}
    assert snapshot.last_run == %{summary: "One reply simulated"}
    assert [%{type: :decision}] = snapshot.workflow_events
    assert snapshot.agent_events == [%{type: "agent.updated"}]

    assert snapshot.inspection == %{
             events: %{
               limit: 6,
               counts: %{"pending" => 0, "failed" => 0},
               recent: [
                 %{
                   event_key: "reply:1",
                   kind: "reply",
                   state: "completed",
                   proposal: nil
                 }
               ]
             },
             people: %{
               counts: %{
                 known: 1,
                 friends: 1,
                 followers: 1,
                 following: 1,
                 mutuals: 1,
                 excluded: 0
               },
               records: [%{did: "did:plc:member", handle: "member.test", friend?: true}],
               visible_count: 1,
               truncated?: false
             },
             effects: %{attention: []},
             sqlite: %{migrations: %{status: "current"}}
           }

    assert snapshot.character == %{
             name: "AgentJido",
             mission: "Make BEAM agent engineering easier to understand.",
             traits: ["calm", "exact"],
             topical_scope: ["BEAM and OTP"]
           }

    assert snapshot.disclosure == %{processing: "Automated processing is disclosed."}
    assert snapshot.reactive_review == %{status: :idle, disabled?: false}
    assert snapshot.proactive_review == %{status: :queued, disabled?: true}
    assert snapshot.overview.autonomy.label == "Observe"
    assert snapshot.overview.connection.label == "Connected"
    assert snapshot.overview.attention == []
    assert hd(snapshot.overview.schedule.items).label == "Timeline review"
    assert hd(snapshot.overview.recent_actions).label == "Reply"
    assert hd(snapshot.inbox.events).event_key == "reply:1"
    assert Enum.find(snapshot.inbox.categories, &(&1.key == "reply")).count == 1
    assert snapshot.inbox.actionable_count == 0
    assert snapshot.drafts.total_count == 0
    assert snapshot.drafts.pending_count == 0
    assert snapshot.people.counts.known == 1
    assert hd(snapshot.people.records).handle == "member.test"
    assert snapshot.image_generation.enabled?
    assert snapshot.image_generation.budget.remaining == 1
    assert snapshot.theme == "dark"
    assert snapshot.setup.required?
    assert snapshot.setup.available?
    assert snapshot.setup.llm_key.configured?
    assert snapshot.settings_editor.available?
    assert snapshot.settings_editor.version == 4
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
        behavior_settings: UnavailableDependency,
        connection_settings: UnavailableDependency,
        console_settings: UnavailableDependency,
        limits_settings: UnavailableDependency,
        image_generation_settings: UnavailableDependency,
        setup_service: UnavailableDependency,
        settings_editor: UnavailableDependency,
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
    refute snapshot.setup.available?
    refute snapshot.setup.required?
    assert snapshot.setup.error == ":agent_not_running"
    refute snapshot.settings_editor.available?
    assert snapshot.settings_editor.error == ":settings_editor_unavailable"
    assert snapshot.character.name == "AgentJido"
    assert snapshot.character.traits == []
    assert snapshot.disclosure == %{}
    assert snapshot.reactive_review.status == :failed
    assert snapshot.reactive_review.disabled?
    assert snapshot.proactive_review.status == :failed
    assert snapshot.proactive_review.disabled?
    assert snapshot.overview.autonomy.label == "Unavailable"
    assert Enum.any?(snapshot.overview.attention, &(&1.key == "runtime"))
    assert snapshot.inbox.events == []
    assert snapshot.drafts.total_count == 0
    assert snapshot.people.records == []
    assert snapshot.people.counts.known == 0
    assert snapshot.image_generation == %{}
    assert snapshot.theme == "system"
    refute snapshot.manual_publish_enabled
    assert snapshot.port == 4040
  end
end
