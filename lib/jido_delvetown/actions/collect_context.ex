defmodule JidoDelvetown.Actions.CollectContext do
  @moduledoc "Collects one bounded Delvetown context for a participation cycle."

  use Jido.Action,
    name: "delvetown_collect_context",
    schema:
      Zoi.object(%{
        kind: Zoi.enum(["reactive", "proactive", "members"]),
        mode: Zoi.enum(["normal", "review"])
      })

  alias JidoDelvetown.{Candidate, Config, InteractionLedger, Protocol, ScanProgress}

  @timeline_limit 5
  @processed_limit 200
  @conversation_limit 50
  @topic_limit 10
  @voice_history_limit 6
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
           }),
         normalized = Candidate.notifications(notifications),
         :ok <- InteractionLedger.observe_candidates(normalized) do
      {:ok,
       base("reactive", mode, state, started_at)
       |> Map.merge(%{
         status: "ready",
         reads: 2,
         membership: Candidate.membership(membership),
         notifications: normalized,
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

  defp collect("members", mode, state, started_at, scan) do
    with {:ok, membership} <- Protocol.query("town.delve.membership.getMembership", %{}),
         {:ok, response} <-
           Protocol.query("town.delve.actor.searchActors", %{
             limit: Config.member_discovery_limit()
           }),
         normalized = Candidate.members(response),
         :ok <- InteractionLedger.observe_candidates(normalized) do
      {:ok,
       base("members", mode, state, started_at)
       |> Map.merge(%{
         status: "ready",
         reads: 2,
         membership: Candidate.membership(membership),
         members: normalized,
         scan: Map.put(scan, :next_cursor, member_watermark(scan.cursor, normalized))
       })}
    else
      {:error, reason} -> failed("members", mode, state, started_at, scan, reason)
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
      members: [],
      recent_posts: [],
      intent: "skip",
      allowed_actions: ["skip"],
      candidate: nil,
      reason: nil,
      selection: %{},
      defer?: false,
      decision: %{},
      effects: 0,
      receipt: nil,
      scan: nil
    }
  end

  defp scan_name("reactive"), do: "notifications"
  defp scan_name("proactive"), do: "timeline"
  defp scan_name("members"), do: "members"

  defp response_cursor(response) when is_map(response) do
    Map.get(response, :cursor) || Map.get(response, "cursor")
  end

  defp response_cursor(_response), do: nil

  defp member_watermark(current, members) do
    members
    |> Enum.map(&"#{&1.indexed_at || ""}|#{&1.id}")
    |> Enum.concat(List.wrap(current))
    |> Enum.max(fn -> nil end)
  end

  defp reset_budget(state) do
    today = Date.utc_today() |> Date.to_iso8601()

    if state.budget.date == today do
      Map.update!(state, :budget, &Map.put_new(&1, :likes, 0))
    else
      Map.put(state, :budget, %{date: today, replies: 0, likes: 0, posts: 0})
    end
  end

  defp prune_history(state) do
    processed = bounded(state.notifications.processed, :at, @processed_limit)
    conversations = bounded(state.conversations, :last_action_at, @conversation_limit)

    state =
      Map.put_new(state, :voice, %{
        recent_formats: [],
        recent_openings: [],
        recent_topics: []
      })

    state
    |> put_in([:notifications, :processed], processed)
    |> Map.put(:conversations, conversations)
    |> put_in(
      [:proactive, :recent_topics],
      Enum.take(state.proactive.recent_topics, @topic_limit)
    )
    |> put_in(
      [:voice, :recent_formats],
      Enum.take(state.voice.recent_formats, @voice_history_limit)
    )
    |> put_in(
      [:voice, :recent_openings],
      Enum.take(state.voice.recent_openings, @voice_history_limit)
    )
    |> put_in(
      [:voice, :recent_topics],
      Enum.take(state.voice.recent_topics, @voice_history_limit)
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
