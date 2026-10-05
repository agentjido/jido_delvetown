defmodule JidoDelvetown.AgentTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Agent
  alias JidoDelvetown.Personality
  alias JidoDelvetown.Repo

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

    scheduler_options =
      Enum.find_value(Agent.definition().plugins, fn
        {Jido.Plugin.Scheduler, options} -> options
        _plugin -> nil
      end)

    assert scheduler_options[:cron_expression] == "*/15 * * * *"
    assert scheduler_options[:job_id] == "delvetown-reactive-participation"
    assert scheduler_options[:signal].type == "jido.delvetown.reactive"
    assert scheduler_options[:signal].data == %{mode: "normal"}

    assert Agent.ai_profile(:operator).result.into == :last_run
    assert Agent.ai_profile(:operator).instructions == Personality.operator_prompt()
  end

  test "application starts the agent with the cron schedule enabled" do
    assert JidoDelvetown.status().schedule_enabled?
    assert JidoDelvetown.status().cron == "*/15 * * * *"
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
          budget: %{date: "2026-10-04", replies: 2, posts: 1},
          proactive: %{last_post_at: "2026-10-04T12:00:00Z", recent_topics: ["OTP"]}
        }
      )

    assert {:ok, first_agent} = Jido.start_agent(instance, saved)
    assert Jido.AgentServer.agent(first_agent).state.last_run == %{summary: "saved"}

    schedule_signal =
      Jido.Signal.new!("jido.delvetown.schedule.ensure", %{}, source: "/test")

    assert {:ok, scheduled} = Jido.AgentServer.call(first_agent, schedule_signal)

    assert scheduled.state.scheduler.cron[Agent.schedule_job_id()].cron_expression ==
             Agent.schedule_cron()

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
    assert restored.state.budget == %{date: "2026-10-04", replies: 2, posts: 1}
    assert restored.state.proactive.recent_topics == ["OTP"]

    assert restored.state.scheduler.cron[Agent.schedule_job_id()].cron_expression ==
             Agent.schedule_cron()
  end
end
