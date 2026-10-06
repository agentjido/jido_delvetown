defmodule JidoDelvetown.Settings.BehaviorTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Settings
  alias JidoDelvetown.Settings.{Behavior, Bootstrap}

  test "reads behavior and conversation policy from SQLite settings" do
    scope = bootstrap_scope()

    refute Behavior.writes_enabled?(scope: scope)
    refute Behavior.manual_publish_enabled?(scope: scope)
    assert {:ok, "openai:gpt-4o-mini"} = Behavior.decision_model(scope: scope)
    assert {:ok, 45_000} = Behavior.decision_timeout(scope: scope)
    assert Behavior.action_enabled?("reply", scope: scope)
    assert Behavior.action_enabled?("skip", scope: scope)

    assert {:ok, %{turn_limit: 4, max_age_hours: 72, non_response_limit: 2}} =
             Behavior.conversation_policy(scope: scope)

    assert {:ok, _updated} =
             Settings.update(
               %{
                 decision_model: "openai:gpt-5-mini",
                 decision_timeout_ms: 60_000,
                 autonomy_mode: "autonomous",
                 enabled_actions: ["like"],
                 manual_publish_enabled: true,
                 dry_run_mark_actioned: true,
                 mark_notifications_seen: true,
                 conversation_turn_limit: 8,
                 conversation_max_age_hours: 24,
                 conversation_non_response_limit: 3
               },
               scope: scope,
               confirmed: [:autonomy_mode, :mark_notifications_seen]
             )

    assert Behavior.writes_enabled?(scope: scope)
    assert Behavior.manual_publish_enabled?(scope: scope)
    assert Behavior.dry_run_mark_actioned?(scope: scope)
    assert Behavior.mark_notifications_seen?(scope: scope)
    refute Behavior.action_enabled?("reply", scope: scope)
    assert Behavior.action_enabled?("like", scope: scope)
    assert Behavior.action_enabled?("skip", scope: scope)

    assert {:ok, ["like", "skip"]} =
             Behavior.filter_enabled_actions(["reply", "like", "skip"], scope: scope)

    assert {:ok, %{turn_limit: 8, max_age_hours: 24, non_response_limit: 3}} =
             Behavior.conversation_policy(scope: scope)
  end

  test "converts OpenAI model names to the ReqLLM model input" do
    assert %{
             id: "gpt-4o-mini",
             model: "gpt-4o-mini",
             provider: :openai,
             base_url: "https://api.openai.com/v1"
           } = Behavior.model_input("openai:gpt-4o-mini")

    assert Behavior.model_input("other:model") == "other:model"
  end

  defp bootstrap_scope do
    scope = "behavior-test-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)
    scope
  end
end
