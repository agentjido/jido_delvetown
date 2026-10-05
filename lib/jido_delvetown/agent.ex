defmodule JidoDelvetown.Agent do
  @moduledoc "Hard-coded Jido AI Agent for scheduled Delvetown participation."

  @id "delvetown-agent"
  @checkpoint_fields [
    :notifications,
    :conversations,
    :proactive,
    :budget,
    :decision,
    :last_cycle,
    :last_run
  ]
  @checkpoint_keys ~w(
    action at budget candidate_id completed_at conversations date decision effects errors
    id intent kind last_action_at last_cycle last_post_at last_record_uri last_run
    last_seen_at notifications posts processed proactive proposal reads reason recent_topics
    replies root_uri skips started_at status summary text topic turns uri
  )a
  @checkpoint_key_lookup Map.new(@checkpoint_keys, &{Atom.to_string(&1), &1})
  @operator_prompt JidoDelvetown.Personality.operator_prompt()

  use Jido.AI.Agent,
    name: "jido_delvetown",
    description: "Runs reactive and proactive Delvetown participation cycles."

  def id, do: @id

  @impl Jido.Agent
  def checkpoint(agent, _context) do
    with {:ok, state} <- agent.state |> Map.take(@checkpoint_fields) |> Jason.encode() do
      {:ok, %{id: agent.id, state: state}}
    end
  end

  @impl Jido.Agent
  def restore(%{id: id, state: state}, _context) when is_binary(state) do
    with {:ok, decoded} <- Jason.decode(state) do
      new(id: id, state: restore_checkpoint_keys(decoded))
    end
  end

  def restore(%{id: id, state: state}, _context) when is_map(state) do
    new(id: id, state: state)
  end

  def restore(%{id: id, last_run: last_run} = checkpoint, _context) do
    # Keep this atom loaded so the safe decoder can read checkpoints from the
    # earlier runtime-controlled schedule format.
    _legacy_schedule_enabled = Map.get(checkpoint, :schedule_enabled)
    new(id: id, state: %{last_run: last_run})
  end

  defp restore_checkpoint_keys(value) when is_list(value),
    do: Enum.map(value, &restore_checkpoint_keys/1)

  defp restore_checkpoint_keys(value) when is_map(value) do
    Map.new(value, fn {key, item} ->
      {Map.get(@checkpoint_key_lookup, key, key), restore_checkpoint_keys(item)}
    end)
  end

  defp restore_checkpoint_keys(value), do: value

  agent do
    schema Zoi.object(%{
             notifications:
               Zoi.object(%{
                 last_seen_at: Zoi.string() |> Zoi.default(""),
                 processed: Zoi.map() |> Zoi.default(%{})
               })
               |> Zoi.default(%{last_seen_at: "", processed: %{}}),
             conversations: Zoi.map() |> Zoi.default(%{}),
             proactive:
               Zoi.object(%{
                 last_post_at: Zoi.string() |> Zoi.default(""),
                 recent_topics: Zoi.list(Zoi.string()) |> Zoi.default([])
               })
               |> Zoi.default(%{last_post_at: "", recent_topics: []}),
             budget:
               Zoi.object(%{
                 date: Zoi.string() |> Zoi.default(""),
                 replies: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
                 posts: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)
               })
               |> Zoi.default(%{date: "", replies: 0, posts: 0}),
             decision: Zoi.map() |> Zoi.default(%{}),
             last_cycle: Zoi.map() |> Zoi.default(%{}),
             last_run: Zoi.map() |> Zoi.default(%{})
           })

    plugin Jido.Plugin.Scheduler,
      config: [
        job_id: "delvetown-reactive-participation",
        cron_expression: "*/15 * * * *",
        signal:
          Jido.Signal.new!(
            "jido.delvetown.reactive",
            %{mode: "normal"},
            source: "/jido_delvetown/cron"
          )
      ]

    ai :operator do
      model "openai:gpt-4o-mini"

      instructions @operator_prompt

      tools do
        action JidoDelvetown.Actions.GetMembership,
          as: :get_membership,
          description: "Get this account's Delvetown membership state"

        action JidoDelvetown.Actions.JoinMembership,
          as: :join_membership,
          description: "Join with the operator-configured invite code"

        action JidoDelvetown.Actions.ListNotifications,
          as: :list_notifications,
          description: "List recent notifications"

        action JidoDelvetown.Actions.GetUnreadCount,
          as: :get_unread_count,
          description: "Get the unread notification count"

        action JidoDelvetown.Actions.UpdateNotificationsSeen,
          as: :update_notifications_seen,
          description: "Mark notifications seen after the cycle"

        action JidoDelvetown.Actions.GetTimeline,
          as: :get_timeline,
          description: "Read the account timeline"

        action JidoDelvetown.Actions.GetFeed,
          as: :get_feed,
          description: "Read one feed by AT URI"

        action JidoDelvetown.Actions.GetAuthorFeed,
          as: :get_author_feed,
          description: "Read recent posts from one actor"

        action JidoDelvetown.Actions.GetPostThread,
          as: :get_post_thread,
          description: "Read a post with its parent and reply context"

        action JidoDelvetown.Actions.GetPosts,
          as: :get_posts,
          description: "Get post views for AT URIs"

        action JidoDelvetown.Actions.SearchPosts,
          as: :search_posts,
          description: "Search Delvetown posts"

        action JidoDelvetown.Actions.GetProfile,
          as: :get_profile,
          description: "Get an actor profile"

        action JidoDelvetown.Actions.ListOwnRecords,
          as: :list_own_records,
          description: "List this account's posts, likes, reposts, or follows"

        action JidoDelvetown.Actions.CreatePost,
          as: :create_post,
          description: "Create a top-level post"

        action JidoDelvetown.Actions.ReplyToPost,
          as: :reply_to_post,
          description: "Reply with post root and parent strong references"

        action JidoDelvetown.Actions.LikePost,
          as: :like_post,
          description: "Like one post"

        action JidoDelvetown.Actions.RepostPost,
          as: :repost_post,
          description: "Repost one post"

        action JidoDelvetown.Actions.FollowActor,
          as: :follow_actor,
          description: "Follow one actor DID"

        action JidoDelvetown.Actions.DeleteRecord,
          as: :delete_record,
          description: "Delete an owned post, like, repost, or follow by AT URI"
      end

      controls do
        timeout 90_000
        max_iterations 12
        max_model_calls 12
        max_tool_calls 24
      end

      observability do
        store_content false
      end

      result(
        Zoi.object(%{
          summary: Zoi.string() |> Zoi.min(1),
          reads: Zoi.integer() |> Zoi.min(0),
          effects: Zoi.integer() |> Zoi.min(0),
          skips: Zoi.integer() |> Zoi.min(0),
          errors: Zoi.list(Zoi.string())
        }),
        into: :last_run,
        max_repairs: 1
      )
    end
  end

  routes do
    signal_source "/jido_delvetown"

    route "jido.delvetown.reactive", JidoDelvetown.ReactiveParticipationCycle,
      defaults: %{mode: "normal"},
      as: :run_reactive_cycle

    route "jido.delvetown.reactive.review", JidoDelvetown.ReactiveParticipationCycle,
      defaults: %{mode: "review"},
      as: :review_reactive_cycle

    route "jido.delvetown.proactive", JidoDelvetown.ProactiveParticipationCycle,
      defaults: %{mode: "normal"},
      as: :run_proactive_cycle

    route "jido.delvetown.proactive.review", JidoDelvetown.ProactiveParticipationCycle,
      defaults: %{mode: "review"},
      as: :review_proactive_cycle

    # Keep restored checkpoints with the earlier scheduled Signal usable.
    route "jido.delvetown.cycle", JidoDelvetown.ReactiveParticipationCycle,
      defaults: %{mode: "normal"},
      as: :legacy_run_cycle

    route "jido.delvetown.review", JidoDelvetown.ReactiveParticipationCycle,
      defaults: %{mode: "review"},
      as: :legacy_review_cycle

    route "jido.delvetown.operator", ai(:operator), as: :operator_query
  end
end
