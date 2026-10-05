defmodule JidoDelvetown.Actions.CollectContext do
  @moduledoc "Collects one bounded Delvetown context for a participation cycle."

  use Jido.Action,
    name: "delvetown_collect_context",
    schema:
      Zoi.object(%{
        kind: Zoi.enum(["reactive", "proactive"]),
        mode: Zoi.enum(["normal", "review"])
      })

  alias JidoDelvetown.{Candidate, Config, Protocol, ScanProgress}

  @timeline_limit 5
  @processed_limit 200
  @conversation_limit 50
  @topic_limit 10
  @retention_seconds 30 * 24 * 60 * 60

  @impl true
  def run(%{kind: kind, mode: mode}, %{agent_state: initial_state}) do
    state = initial_state |> reset_budget() |> prune_history()
    started_at = now()

    case ScanProgress.claim(scan_name(kind)) do
      {:ok, scan} -> collect(kind, mode, state, started_at, scan)
      {:error, :scan_in_progress} -> busy(kind, mode, state, started_at)
      {:error, reason} -> failed(kind, mode, state, started_at, nil, reason)
    end
  end

  defp collect("reactive", mode, state, started_at, scan) do
    with {:ok, membership} <- Protocol.query("town.delve.membership.getMembership", %{}),
         {:ok, notifications} <-
           Protocol.query("town.delve.notification.listNotifications", %{
             cursor: scan.cursor,
             limit: Config.notification_limit()
           }) do
      {:ok,
       base("reactive", mode, state, started_at)
       |> Map.merge(%{
         status: "ready",
         reads: 2,
         membership: Candidate.membership(membership),
         notifications: Candidate.notifications(notifications),
         scan: Map.put(scan, :next_cursor, response_cursor(notifications))
       })}
    else
      {:error, reason} -> failed("reactive", mode, state, started_at, scan, reason)
    end
  end

  defp collect("proactive", mode, state, started_at, scan) do
    with {:ok, membership} <- Protocol.query("town.delve.membership.getMembership", %{}),
         {:ok, timeline} <-
           Protocol.query("town.delve.feed.getTimeline", %{
             cursor: scan.cursor,
             limit: @timeline_limit
           }) do
      {:ok,
       base("proactive", mode, state, started_at)
       |> Map.merge(%{
         status: "ready",
         reads: 2,
         membership: Candidate.membership(membership),
         recent_posts: Candidate.posts(timeline),
         scan: Map.put(scan, :next_cursor, response_cursor(timeline))
       })}
    else
      {:error, reason} -> failed("proactive", mode, state, started_at, scan, reason)
    end
  end

  defp failed(kind, mode, state, started_at, scan, reason) do
    {:ok,
     kind
     |> base(mode, state, started_at)
     |> Map.merge(%{
       status: "failed",
       stage: "context_read",
       scan: scan,
       errors: [error_text(reason)]
     })}
  end

  defp busy(kind, mode, state, started_at) do
    {:ok,
     kind
     |> base(mode, state, started_at)
     |> Map.merge(%{
       status: "skipped",
       stage: "scan_claim",
       reason: "scan_in_progress",
       defer?: true
     })}
  end

  defp base(kind, mode, state, started_at) do
    %{
      kind: kind,
      mode: mode,
      state: state,
      status: "new",
      stage: nil,
      started_at: started_at,
      reads: 0,
      errors: [],
      membership: %{},
      notifications: [],
      recent_posts: [],
      intent: "skip",
      allowed_actions: ["skip"],
      candidate: nil,
      reason: nil,
      defer?: false,
      decision: %{},
      effects: 0,
      receipt: nil,
      scan: nil
    }
  end

  defp scan_name("reactive"), do: "notifications"
  defp scan_name("proactive"), do: "timeline"

  defp response_cursor(response) when is_map(response) do
    Map.get(response, :cursor) || Map.get(response, "cursor")
  end

  defp response_cursor(_response), do: nil

  defp reset_budget(state) do
    today = Date.utc_today() |> Date.to_iso8601()

    if state.budget.date == today,
      do: state,
      else: Map.put(state, :budget, %{date: today, replies: 0, posts: 0})
  end

  defp prune_history(state) do
    processed = bounded(state.notifications.processed, :at, @processed_limit)
    conversations = bounded(state.conversations, :last_action_at, @conversation_limit)

    state
    |> put_in([:notifications, :processed], processed)
    |> Map.put(:conversations, conversations)
    |> put_in(
      [:proactive, :recent_topics],
      Enum.take(state.proactive.recent_topics, @topic_limit)
    )
  end

  defp bounded(records, time_key, limit) do
    records
    |> Enum.filter(fn {_key, record} -> recent?(Map.get(record, time_key)) end)
    |> Enum.sort_by(fn {_key, record} -> Map.get(record, time_key, "") end, :desc)
    |> Enum.take(limit)
    |> Map.new()
  end

  defp recent?(value) when is_binary(value) do
    with {:ok, timestamp, _offset} <- DateTime.from_iso8601(value) do
      DateTime.diff(DateTime.utc_now(), timestamp, :second) <= @retention_seconds
    else
      _invalid -> false
    end
  end

  defp recent?(_value), do: false

  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(_reason), do: "operation_failed"

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
