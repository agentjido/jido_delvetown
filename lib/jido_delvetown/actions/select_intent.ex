defmodule JidoDelvetown.Actions.SelectIntent do
  @moduledoc "Selects one intent for a reactive or proactive cycle."

  use Jido.Action,
    name: "delvetown_select_intent",
    schema: Zoi.object(%{cycle: Zoi.map()})

  alias JidoDelvetown.{Candidate, Config, Protocol, Session}

  @direct_reasons ["mention", "reply"]
  @deferred_reasons ["follow"]
  @reply_limit 3
  @post_limit 1
  @actions %{
    "answer_direct_request" => ["reply", "skip"],
    "join_useful_discussion" => ["reply", "like", "repost", "skip"],
    "publish_daily_note" => ["post", "skip"],
    "skip" => ["skip"]
  }

  @impl true
  def run(%{cycle: %{status: "failed"} = cycle}, _context), do: {:ok, cycle}

  def run(%{cycle: %{kind: "reactive"} = cycle}, _context) do
    state = remember_ignored_notifications(cycle.state, cycle.notifications)
    cycle = Map.put(cycle, :state, state)
    direct = Enum.find(cycle.notifications, &direct_candidate?(&1, state))

    cond do
      direct && state.budget.replies >= @reply_limit ->
        {:ok, select(cycle, "skip", direct, "reply_budget_exhausted", true)}

      direct ->
        select_with_thread(cycle, "answer_direct_request", direct)

      true ->
        {:ok, select(cycle, "skip", nil, "no_direct_request")}
    end
  end

  def run(%{cycle: %{kind: "proactive"} = cycle}, _context),
    do: select_proactive(cycle)

  @doc false
  def allowed_actions(intent), do: Map.fetch(@actions, intent)

  defp select_proactive(cycle) do
    posts =
      cycle.recent_posts
      |> Enum.reject(&own_post?/1)
      |> Enum.reject(&processed?(cycle.state, &1.id))

    discussion = Enum.find(posts, &Candidate.question?/1)

    cond do
      discussion && cycle.state.budget.replies < @reply_limit ->
        select_with_thread(%{cycle | recent_posts: posts}, "join_useful_discussion", discussion)

      daily_note_due?(cycle.state) ->
        candidate = %{
          id: "daily:#{cycle.state.budget.date}",
          uri: nil,
          cid: nil,
          root: nil,
          author: %{},
          text: ""
        }

        {:ok, select(%{cycle | recent_posts: posts}, "publish_daily_note", candidate)}

      true ->
        reason = if discussion, do: "reply_budget_exhausted", else: "no_eligible_work"
        {:ok, select(cycle, "skip", discussion, reason, not is_nil(discussion))}
    end
  end

  defp select_with_thread(cycle, intent, %{uri: uri} = candidate) when is_binary(uri) do
    case Protocol.query("town.delve.feed.getPostThread", %{
           uri: uri,
           depth: 6,
           parent_height: 6
         }) do
      {:ok, response} ->
        thread = Candidate.thread(response)
        root = get_in(thread || %{}, [:post, :root]) || candidate.root
        candidate = candidate |> Map.put(:thread, thread) |> Map.put(:root, root)
        {:ok, cycle |> Map.update!(:reads, &(&1 + 1)) |> select(intent, candidate)}

      {:error, reason} ->
        {:ok,
         cycle
         |> Map.update!(:reads, &(&1 + 1))
         |> Map.merge(%{status: "failed", stage: "thread_read", errors: [error_text(reason)]})}
    end
  end

  defp select_with_thread(cycle, _intent, _candidate) do
    {:ok,
     Map.merge(cycle, %{status: "failed", stage: "thread_read", errors: ["missing_post_uri"]})}
  end

  defp select(cycle, intent, candidate, reason \\ nil, defer? \\ false) do
    Map.merge(cycle, %{
      intent: intent,
      allowed_actions: Map.fetch!(@actions, intent),
      candidate: candidate,
      reason: reason,
      defer?: defer?
    })
  end

  defp remember_ignored_notifications(state, notifications) do
    Enum.reduce(notifications, state, fn notification, acc ->
      if notification.unread? and
           notification.reason not in (@direct_reasons ++ @deferred_reasons) and
           not processed?(acc, notification.id) do
        put_processed(acc, notification, "skip", "skip", "ignored")
      else
        acc
      end
    end)
  end

  defp direct_candidate?(notification, state) do
    notification.unread? and notification.reason in @direct_reasons and
      not processed?(state, notification.id)
  end

  defp processed?(state, id) do
    case state.notifications.processed[id] do
      nil -> false
      %{status: "failed"} -> false
      %{status: "proposed"} -> not Config.write_enabled?()
      _record -> true
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

  defp daily_note_due?(state), do: state.budget.posts < @post_limit

  defp own_post?(%{author: %{did: did}}) when is_binary(did) do
    case Session.status() do
      %{did: ^did} -> true
      _status -> false
    end
  catch
    :exit, _reason -> false
  end

  defp own_post?(_post), do: false

  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(_reason), do: "operation_failed"

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
