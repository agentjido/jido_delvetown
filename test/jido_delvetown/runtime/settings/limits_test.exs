defmodule JidoDelvetown.Settings.LimitsTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Settings
  alias JidoDelvetown.Settings.{Bootstrap, Limits}

  test "reads one validated limit snapshot from SQLite settings" do
    scope = bootstrap_scope()

    assert {:ok, limits} = Limits.current(scope: scope)
    assert limits.notification_limit == 20
    assert limits.daily_reply_limit == 3
    assert limits.daily_post_limit == 1
    assert limits.daily_welcome_limit == 2
    assert limits.daily_follow_limit == 5
    assert limits.daily_like_limit == 5
    assert limits.daily_image_generation_limit == 1
    assert limits.like_actor_cooldown_hours == 24
    assert limits.like_candidate_max_age_hours == 48
    assert limits.member_discovery_limit == 20
    assert limits.member_max_age_hours == 24
    assert limits.friend_sync_limit == 1_000

    assert {:ok, %{turn_limit: 4, max_age_hours: 72, non_response_limit: 2}} =
             Limits.conversation_policy(scope: scope)

    assert {:ok, _updated} =
             Settings.update(
               %{
                 notification_limit: 10,
                 daily_reply_limit: 8,
                 daily_post_limit: 2,
                 daily_welcome_limit: 4,
                 daily_follow_limit: 6,
                 daily_like_limit: 9,
                 daily_image_generation_limit: 4,
                 like_actor_cooldown_hours: 12,
                 like_candidate_max_age_hours: 36,
                 member_discovery_limit: 30,
                 member_max_age_hours: 48,
                 friend_sync_limit: 500,
                 conversation_turn_limit: 8,
                 conversation_max_age_hours: 24,
                 conversation_non_response_limit: 3
               },
               scope: scope
             )

    assert {:ok, updated} = Limits.current(scope: scope)
    assert updated.notification_limit == 10
    assert updated.daily_reply_limit == 8
    assert updated.daily_post_limit == 2
    assert updated.daily_welcome_limit == 4
    assert updated.daily_follow_limit == 6
    assert updated.daily_like_limit == 9
    assert updated.daily_image_generation_limit == 4
    assert updated.like_actor_cooldown_hours == 12
    assert updated.like_candidate_max_age_hours == 36
    assert updated.member_discovery_limit == 30
    assert updated.member_max_age_hours == 48
    assert updated.friend_sync_limit == 500

    assert {:ok, %{turn_limit: 8, max_age_hours: 24, non_response_limit: 3}} =
             Limits.conversation_policy(scope: scope)
  end

  test "rejects unknown limit keys" do
    assert {:error, {:unknown_limit, :unknown}} = Limits.fetch(:unknown)
  end

  defp bootstrap_scope do
    scope = "limits-test-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)
    scope
  end
end
