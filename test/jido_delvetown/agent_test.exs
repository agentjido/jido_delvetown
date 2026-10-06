defmodule JidoDelvetown.AgentTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Agent
  alias JidoDelvetown.Automation
  alias JidoDelvetown.Personality
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Workers.FriendSyncWorker
  alias JidoDelvetown.Workers.MemberDiscoveryWorker
  alias JidoDelvetown.Workers.ProactiveReviewWorker
  alias JidoDelvetown.Workers.ReactiveParticipationWorker

  test "the hard-coded DSL exposes the complete participation tool set" do
    tool_names = Agent.ai_profile(:operator).tools |> Enum.map(& &1.name) |> MapSet.new()

    assert tool_names ==
             MapSet.new(~w(
               get_membership
               join_membership
               list_notifications
               get_unread_count
               update_notifications_seen
               get_timeline
               get_feed
               get_author_feed
               get_post_thread
               get_posts
               search_posts
               get_profile
               list_own_records
               create_post
               reply_to_post
               like_post
               repost_post
               follow_actor
               delete_record
             ))

    refute Enum.any?(Agent.definition().plugins, fn
             {Jido.Plugin.Scheduler, _options} -> true
             Jido.Plugin.Scheduler -> true
             _plugin -> false
           end)

    assert Agent.ai_profile(:operator).result.into == :last_run
    assert Agent.ai_profile(:operator).instructions == Personality.operator_prompt()
  end

  test "application starts Oban with all cron schedules" do
    assert JidoDelvetown.status().schedule_enabled?
    assert JidoDelvetown.status().cron == "*/15 * * * *"
    assert JidoDelvetown.status().proactive_review_cron == "5,35 * * * *"
    assert JidoDelvetown.status().friend_sync_cron == "17 * * * *"
    assert is_pid(Oban.whereis(Oban))

    assert Automation.crontab() == [
             {"*/15 * * * *", ReactiveParticipationWorker},
             {"5,35 * * * *", ProactiveReviewWorker},
             {"7 * * * *", MemberDiscoveryWorker},
             {"17 * * * *", FriendSyncWorker}
           ]
  end

  test "the named Jido instance owns the Delvetown agent" do
    assert {:ok, agent_server} = JidoDelvetown.agent_server()

    assert is_pid(Process.whereis(JidoDelvetown.Jido))
    assert is_pid(agent_server)
    assert {Agent.id(), agent_server} in JidoDelvetown.Jido.list_agents()

    assert Enum.any?(
             DynamicSupervisor.which_children(Jido.agent_supervisor_name(JidoDelvetown.Jido)),
             fn {_id, pid, _type, _modules} -> pid == agent_server end
           )
  end

  test "the SQLite checkpoint restores the agent state" do
    suffix = System.unique_integer([:positive])
    instance = :"jido_delvetown_checkpoint_#{suffix}"
    namespace = "jido-delvetown-test/#{suffix}"

    options = [
      name: instance,
      namespace: namespace,
      persistence: {Jido.Persistence.Ecto, repo: Repo}
    ]

    id = "checkpoint-agent"
    ref = Jido.Agent.Ref.new!(namespace: namespace, partition: nil, id: id)
    key = Jido.Persistence.agent_key(ref)
    :ok = Jido.Persistence.Ecto.delete(key, repo: Repo)

    {:ok, first_instance} = Jido.start_link(options)
    Process.unlink(first_instance)

    saved =
      Agent.new!(
        id: id,
        state: %{
          last_run: %{summary: "saved"},
          budget: %{date: "2026-10-04", replies: 2, likes: 4, posts: 1},
          notifications: %{
            last_seen_at: "2026-10-04T12:00:00Z",
            processed: %{
              "post:one" => %{
                id: "post:one",
                action: "like",
                status: "simulated",
                at: "2026-10-04T12:00:00Z"
              }
            }
          },
          proactive: %{last_post_at: "2026-10-04T12:00:00Z", recent_topics: ["OTP"]}
        }
      )

    assert {:ok, first_agent} = Jido.start_agent(instance, saved)
    assert Jido.AgentServer.agent(first_agent).state.last_run == %{summary: "saved"}

    :ok = Supervisor.stop(first_instance)

    {:ok, second_instance} = Jido.start_link(options)
    Process.unlink(second_instance)

    on_exit(fn ->
      if Process.alive?(second_instance), do: Supervisor.stop(second_instance)
      Jido.Persistence.Ecto.delete(key, repo: Repo)
    end)

    assert {:ok, second_agent} = Jido.start_agent(instance, Agent, id: id)
    restored = Jido.AgentServer.agent(second_agent)
    assert restored.state.last_run == %{summary: "saved"}
    assert restored.state.budget == %{date: "2026-10-04", replies: 2, likes: 4, posts: 1}
    assert restored.state.notifications.processed["post:one"].action == "like"
    assert restored.state.notifications.processed["post:one"].status == "simulated"
    assert restored.state.proactive.recent_topics == ["OTP"]
  end
end
