defmodule JidoDelvetown.Actions.SelectIntent do
  @moduledoc "Selects one intent for a reactive or proactive cycle."

  use Jido.Action,
    name: "delvetown_select_intent",
    schema: Zoi.object(%{cycle: Zoi.map()})

  alias JidoDelvetown.{
    ActorMemory,
    Candidate,
    ConversationMemory,
    ConversationPolicy,
    EngagementRanker,
    InteractionEvents,
    OptOut,
    OutgoingLikePolicy,
    Protocol,
    Session
  }

  alias JidoDelvetown.Settings.Behavior

  @direct_reasons ["mention", "reply"]
  @deferred_reasons ["follow"]
  @actions %{
    "answer_direct_request" => ["reply", "skip"],
    "continue_conversation" => ["reply", "skip"],
    "respond_to_new_follow" => ["acknowledge", "follow", "welcome", "skip"],
    "welcome_new_member" => ["welcome", "skip"],
    "join_useful_discussion" => ["reply", "like", "repost", "skip"],
    "publish_daily_note" => ["post", "skip"],
    "skip" => ["skip"]
  }

  @impl true
  def run(%{cycle: %{status: "failed"} = cycle}, _context), do: {:ok, cycle}

  def run(%{cycle: %{kind: "reactive"} = cycle}, _context) do
    state = remember_ignored_notifications(cycle.state, cycle.notifications)
    cycle = Map.put(cycle, :state, state)
    limits = cycle.limits

    direct =
      cycle.notifications
      |> Enum.filter(&direct_candidate?(&1, state))
      |> rank(:direct, state, limits)

    follow =
      cycle.notifications
      |> Enum.filter(&follow_candidate?(&1, state))
      |> rank(:follow, state, limits)

    follow_up = ConversationPolicy.evaluate(direct)

    cond do
      direct && opt_out?(direct) ->
        candidate = Map.put(direct, :opt_out?, OptOut.requested?(direct.text))
        {:ok, select(cycle, "skip", candidate, "actor_opt_out")}

      direct && state.budget.replies >= limits.daily_reply_limit ->
        {:ok, select(cycle, "skip", direct, "reply_budget_exhausted", true)}

      direct && match?({:skip, _reason}, follow_up) ->
        {:skip, reason} = follow_up
        {:ok, select(cycle, "skip", direct, reason)}

      direct && follow_up == :continue ->
        select_with_thread(cycle, "continue_conversation", direct)

      direct ->
        select_with_thread(cycle, "answer_direct_request", direct)

      follow && opt_out?(follow) ->
        {:ok, select(cycle, "skip", follow, "actor_opt_out")}

      follow && not valid_actor?(follow) ->
        {:ok, select(cycle, "skip", follow, "missing_actor_did")}

      follow && prior_contact?(follow) ->
        {:ok, select(cycle, "skip", follow, "follow_actor_already_contacted")}

      follow ->
        selected = select(cycle, "respond_to_new_follow", follow)
        {:ok, Map.put(selected, :allowed_actions, follow_actions(state, limits))}

      true ->
        {:ok, select(cycle, "skip", nil, "no_direct_request")}
    end
  end

  def run(%{cycle: %{kind: "proactive"} = cycle}, _context),
    do: select_proactive(cycle)

  def run(%{cycle: %{kind: "members"} = cycle}, _context),
    do: select_member(cycle)

  @doc false
  def allowed_actions(intent), do: Map.fetch(@actions, intent)

  defp select_proactive(cycle) do
    limits = cycle.limits

    evaluated_posts =
      cycle.recent_posts
      |> Enum.map(&add_memory/1)
      |> Enum.map(&attach_like_eligibility(&1, cycle.state, limits))

    posts = Enum.filter(evaluated_posts, &like_eligible?/1)

    discussion =
      posts
      |> Enum.filter(&Candidate.question?/1)
      |> rank(:useful_discussion, cycle.state, limits)

    rejected_discussion =
      evaluated_posts
      |> Enum.reject(&like_eligible?/1)
      |> Enum.filter(&Candidate.question?/1)
      |> rank(:useful_discussion, cycle.state, limits)

    cond do
      InteractionEvents.pending?(@direct_reasons) ->
        {:ok, select(cycle, "skip", nil, "direct_request_pending")}

      discussion ->
        select_with_thread(
          %{cycle | recent_posts: posts},
          "join_useful_discussion",
          discussion,
          discussion_actions(cycle.state, limits)
        )

      rejected_discussion ->
        reason = get_in(rejected_discussion, [:like_eligibility, :reason])

        {:ok,
         select(
           %{cycle | recent_posts: posts},
           "skip",
           rejected_discussion,
           reason,
           OutgoingLikePolicy.temporary_reason?(reason)
         )}

      daily_note_due?(cycle.state, limits) ->
        candidate =
          %{
            id: "daily:#{cycle.state.budget.date}",
            uri: nil,
            cid: nil,
            root: nil,
            author: %{},
            text: ""
          }
          |> then(&EngagementRanker.best([&1], :original_post, cycle.state, limits: limits))

        {:ok, select(%{cycle | recent_posts: posts}, "publish_daily_note", candidate)}

      true ->
        {:ok, select(cycle, "skip", nil, "no_eligible_work")}
    end
  end

  defp select_member(cycle) do
    limits = cycle.limits

    candidate =
      cycle.members
      |> Enum.filter(&InteractionEvents.processable?(&1.event_key))
      |> rank(:new_member, cycle.state, limits)

    cond do
      is_nil(candidate) ->
        {:ok, select(cycle, "skip", nil, "no_new_member")}

      own_actor?(candidate) ->
        {:ok, select(cycle, "skip", candidate, "agent_account")}

      not valid_member_context?(candidate) ->
        {:ok, select(cycle, "skip", candidate, "insufficient_member_context")}

      member_too_old?(candidate, limits) ->
        {:ok, select(cycle, "skip", candidate, "member_too_old")}

      opt_out?(candidate) ->
        {:ok, select(cycle, "skip", candidate, "actor_opt_out")}

      prior_contact?(candidate) ->
        {:ok, select(cycle, "skip", candidate, "member_already_contacted")}

      InteractionEvents.pending?(@direct_reasons) ->
        {:ok, select(cycle, "skip", candidate, "direct_request_pending", true)}

      welcome_budget_exhausted?(cycle.state, limits) ->
        {:ok, select(cycle, "skip", candidate, "welcome_budget_exhausted", true)}

      true ->
        {:ok, select(cycle, "welcome_new_member", candidate)}
    end
  end

  defp select_with_thread(cycle, intent, candidate, allowed_actions \\ nil)

  defp select_with_thread(cycle, intent, %{uri: uri} = candidate, allowed_actions)
       when is_binary(uri) do
    case Protocol.query("town.delve.feed.getPostThread", %{
           uri: uri,
           depth: 6,
           parent_height: 6
         }) do
      {:ok, response} ->
        thread = Candidate.thread(response)
        root = candidate.root || get_in(thread || %{}, [:post, :root])

        candidate =
          candidate
          |> Map.put(:thread, thread)
          |> Map.put(:root, root)
          |> add_memory()

        selected = cycle |> Map.update!(:reads, &(&1 + 1)) |> select(intent, candidate)
        {:ok, maybe_put_allowed_actions(selected, allowed_actions)}

      {:error, reason} ->
        {:ok,
         cycle
         |> Map.update!(:reads, &(&1 + 1))
         |> Map.merge(%{status: "failed", stage: "thread_read", errors: [error_text(reason)]})}
    end
  end

  defp select_with_thread(cycle, _intent, _candidate, _allowed_actions) do
    {:ok,
     Map.merge(cycle, %{status: "failed", stage: "thread_read", errors: ["missing_post_uri"]})}
  end

  defp select(cycle, intent, candidate, reason \\ nil, defer? \\ false) do
    selection = selection(candidate, reason)

    Map.merge(cycle, %{
      intent: intent,
      allowed_actions: Map.fetch!(@actions, intent),
      candidate: candidate,
      reason: selection.reason,
      selection: selection,
      defer?: defer?
    })
  end

  defp remember_ignored_notifications(state, notifications) do
    Enum.reduce(notifications, state, fn notification, acc ->
      if notification.reason not in (@direct_reasons ++ @deferred_reasons) and
           not processed?(acc, notification.id) do
        put_processed(acc, notification, "skip", "skip", "ignored")
      else
        acc
      end
    end)
  end

  defp direct_candidate?(notification, state) do
    notification.reason in @direct_reasons and
      not processed?(state, notification.id) and
      InteractionEvents.processable?(notification.event_key)
  end

  defp follow_candidate?(notification, state) do
    notification.reason == "follow" and
      not processed?(state, notification.id) and
      InteractionEvents.processable?(notification.event_key)
  end

  defp add_memory(nil), do: nil

  defp add_memory(candidate),
    do: Map.put(candidate, :memory, memory_context(candidate))

  defp memory_context(candidate) do
    %{
      actor: ActorMemory.context(get_in(candidate, [:author, :did])),
      conversation: ConversationMemory.context(get_in(candidate, [:root, :uri]))
    }
  end

  defp attach_like_eligibility(candidate, state, limits) do
    case OutgoingLikePolicy.evaluate(candidate, state, limits: limits) do
      :ok ->
        Map.put(candidate, :like_eligibility, %{status: "eligible", reason: nil})

      {:skip, reason} ->
        Map.put(candidate, :like_eligibility, %{status: "excluded", reason: reason})
    end
  end

  defp like_eligible?(candidate),
    do: get_in(candidate, [:like_eligibility, :status]) == "eligible"

  defp discussion_actions(state, limits) do
    if state.budget.replies < limits.daily_reply_limit,
      do: Map.fetch!(@actions, "join_useful_discussion"),
      else: ["like", "skip"]
  end

  defp follow_actions(state, limits) do
    ["acknowledge"]
    |> maybe_add_budgeted_action(
      "follow",
      Map.get(state.budget, :follows, 0) < limits.daily_follow_limit
    )
    |> maybe_add_budgeted_action(
      "welcome",
      Map.get(state.budget, :welcomes, 0) < limits.daily_welcome_limit
    )
    |> Kernel.++(["skip"])
  end

  defp maybe_add_budgeted_action(actions, action, true), do: actions ++ [action]
  defp maybe_add_budgeted_action(actions, _action, false), do: actions

  defp maybe_put_allowed_actions(cycle, nil), do: cycle
  defp maybe_put_allowed_actions(cycle, actions), do: Map.put(cycle, :allowed_actions, actions)

  defp rank(candidates, opportunity, state, limits) do
    candidates
    |> Enum.map(&add_memory/1)
    |> EngagementRanker.best(opportunity, state, limits: limits)
  end

  defp selection(nil, reason), do: %{score: nil, factors: %{}, reason: reason}

  defp selection(candidate, reason) do
    candidate
    |> Map.get(:engagement_rank, %{score: nil, factors: %{}, reason: nil})
    |> Map.put(:reason, reason || get_in(candidate, [:engagement_rank, :reason]))
  end

  defp opt_out?(candidate) do
    OptOut.requested?(candidate.text) or get_in(candidate, [:memory, :actor, :opted_out]) == true
  end

  defp valid_actor?(candidate), do: is_binary(get_in(candidate, [:author, :did]))

  defp prior_contact?(candidate) do
    case get_in(candidate, [:memory, :actor]) do
      %{contact_count: count} when count > 0 -> true
      %{welcome_status: "completed"} -> true
      _actor -> false
    end
  end

  defp own_actor?(%{author: %{did: did}}) when is_binary(did) do
    case Session.status() do
      %{did: ^did} -> true
      _status -> false
    end
  catch
    :exit, _reason -> false
  end

  defp own_actor?(_candidate), do: false

  defp valid_member_context?(candidate) do
    valid_actor?(candidate) and is_binary(get_in(candidate, [:author, :handle]))
  end

  defp member_too_old?(%{indexed_at: indexed_at}, limits) when is_binary(indexed_at) do
    case DateTime.from_iso8601(indexed_at) do
      {:ok, joined_at, _offset} ->
        DateTime.diff(DateTime.utc_now(), joined_at, :hour) > limits.member_max_age_hours

      _invalid ->
        true
    end
  end

  defp member_too_old?(_candidate, _limits), do: true

  defp welcome_budget_exhausted?(state, limits) do
    now = DateTime.utc_now()
    start_of_day = DateTime.new!(DateTime.to_date(now), ~T[00:00:00], "Etc/UTC")

    count =
      max(
        Map.get(state.budget, :welcomes, 0),
        InteractionEvents.outreach_count("welcome", start_of_day)
      )

    count >= limits.daily_welcome_limit
  end

  defp processed?(state, id) do
    case state.notifications.processed[id] do
      nil ->
        false

      %{status: "failed"} ->
        false

      %{status: "proposed"} ->
        not Behavior.writes_enabled?() and not Behavior.dry_run_mark_actioned?()

      _record ->
        true
    end
  end

  defp put_processed(state, candidate, intent, action, status) do
    record = %{
      id: candidate.id,
      uri: Map.get(candidate, :uri),
      intent: intent,
      action: action,
      status: status,
      at: now()
    }

    processed = Map.put(state.notifications.processed, candidate.id, record)
    put_in(state, [:notifications, :processed], processed)
  end

  defp daily_note_due?(state, limits), do: state.budget.posts < limits.daily_post_limit

  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(_reason), do: "operation_failed"

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
