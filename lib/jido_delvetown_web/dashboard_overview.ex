defmodule JidoDelvetownWeb.DashboardOverview do
  @moduledoc false

  alias Oban.Cron.Expression

  @schedules [
    {:reactive, "Inbox review", :cron},
    {:proactive, "Timeline review", :proactive_review_cron},
    {:members, "New-member discovery", :member_discovery_cron},
    {:friends, "Friend sync", :friend_sync_cron}
  ]

  @budgets [
    {:replies, "Replies and reposts", :daily_reply_limit},
    {:posts, "Posts", :daily_post_limit},
    {:welcomes, "Welcomes", :daily_welcome_limit},
    {:follows, "Follows", :daily_follow_limit},
    {:likes, "Likes", :daily_like_limit}
  ]

  @action_event_types ~w(decision create_record delete_record manual_publish)

  @spec build(map(), map(), [map()], map(), DateTime.t(), keyword()) :: map()
  def build(status, inspection, workflow_events, limits, now, opts \\ []) do
    %{
      autonomy: autonomy(status),
      connection: connection(status),
      attention: attention(status, inspection, opts),
      schedule: schedule(status, now),
      budgets: budgets(status, limits),
      recent_actions: recent_actions(workflow_events)
    }
  end

  defp autonomy(status) do
    mode = map_value(status, :autonomy_mode, "unknown")

    case mode do
      "observe" ->
        %{
          mode: mode,
          label: "Observe",
          state: "safe",
          detail: "Collect activity and prepare local proposals. Protocol writes stay off."
        }

      "review" ->
        %{
          mode: mode,
          label: "Review",
          state: "idle",
          detail: "Save selected actions for operator review. Nothing publishes automatically."
        }

      "autonomous" ->
        %{
          mode: mode,
          label: "Autonomous",
          state: "attention",
          detail: "Enabled actions can create public DelveTown records without another approval."
        }

      _mode ->
        %{
          mode: "unknown",
          label: "Unavailable",
          state: "attention",
          detail: "The current autonomy mode could not be read."
        }
    end
  end

  defp connection(status) do
    session = map_value(status, :session, %{})
    connected? = map_value(session, :connected?, false)
    credentials? = map_value(status, :credentials_configured?, false)

    cond do
      connected? ->
        handle = map_value(session, :handle)

        %{
          connected?: true,
          label: "Connected",
          state: "healthy",
          detail: if(present?(handle), do: "Signed in as @#{handle}.", else: "Session is active.")
        }

      credentials? ->
        %{
          connected?: false,
          label: "Ready",
          state: "idle",
          detail: "Credentials are saved. The session connects when work needs it."
        }

      true ->
        %{
          connected?: false,
          label: "Setup required",
          state: "attention",
          detail: "Add a DelveTown handle and app password before work can run."
        }
    end
  end

  defp attention(status, inspection, opts) do
    []
    |> maybe_add(Keyword.get(opts, :status_error), %{
      key: "runtime",
      label: "Agent runtime is unavailable",
      detail: "Start the local Agent runtime before scheduled work can continue.",
      state: "attention"
    })
    |> maybe_add(not map_value(status, :credentials_configured?, false), %{
      key: "credentials",
      label: "DelveTown credentials are missing",
      detail: "Complete first-run setup to enable authenticated reads.",
      state: "attention"
    })
    |> add_count_attention(
      inspection_list(inspection, [:effects, :attention]) |> length(),
      "effects",
      "effect needs reconciliation",
      "effects need reconciliation",
      "Inspect reserved, uncertain, or failed effects before another write."
    )
    |> add_count_attention(
      inspection_count(inspection, [:events, :counts], "failed"),
      "failed-events",
      "event failed",
      "events failed",
      "Review the failed events and local logs."
    )
    |> add_count_attention(
      inspection_count(inspection, [:events, :counts], "pending"),
      "pending-events",
      "proposal waits for review",
      "proposals wait for review",
      "Open the Inbox to review pending participation proposals.",
      "idle"
    )
    |> maybe_add(migration_attention?(inspection), %{
      key: "migrations",
      label: "SQLite migrations are pending",
      detail: "Restart the application and check the migration log.",
      state: "attention"
    })
    |> review_attention(Keyword.get(opts, :reactive_review), "reactive")
    |> review_attention(Keyword.get(opts, :proactive_review), "proactive")
  end

  defp schedule(status, now) do
    enabled? = map_value(status, :schedule_enabled?, false)

    items =
      if enabled? do
        @schedules
        |> Enum.map(&schedule_item(&1, status, now))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.next_at, DateTime)
      else
        []
      end

    %{enabled?: enabled?, items: items}
  end

  defp schedule_item({key, label, field}, status, now) do
    cron = map_value(status, field)

    with cron when is_binary(cron) and cron != "" <- cron,
         {:ok, expression} <- Expression.parse(cron),
         %DateTime{} = next_at <- Expression.next_at(expression, now) do
      %{
        key: Atom.to_string(key),
        label: label,
        cron: cron,
        next_at: next_at,
        next_at_iso8601: DateTime.to_iso8601(next_at),
        relative: relative_time(next_at, now)
      }
    else
      _result -> nil
    end
  end

  defp budgets(status, limits) do
    used = map_value(status, :budget, %{})

    Enum.map(@budgets, fn {key, label, limit_key} ->
      count = non_negative_integer(map_value(used, key, 0))
      limit = non_negative_integer(map_value(limits, limit_key, 0))

      %{
        key: Atom.to_string(key),
        label: label,
        used: count,
        limit: limit,
        remaining: max(limit - count, 0),
        percent: budget_percent(count, limit)
      }
    end)
  end

  defp recent_actions(events) when is_list(events) do
    events
    |> Enum.filter(&(event_type(&1) in @action_event_types))
    |> Enum.map(&recent_action/1)
    |> Enum.take(5)
  end

  defp recent_actions(_events), do: []

  defp recent_action(event) do
    type = event_type(event)
    data = map_value(event, :data, %{})

    %{
      type: type,
      label: action_label(type, data),
      status: action_status(type, data),
      detail: action_detail(type, data),
      at: map_value(event, :at)
    }
  end

  defp action_label("decision", data),
    do: data |> map_value(:action, "participation") |> humanize()

  defp action_label("create_record", _data), do: "Published record"
  defp action_label("delete_record", _data), do: "Deleted record"
  defp action_label("manual_publish", _data), do: "Manual publish"
  defp action_label(_type, _data), do: "Agent action"

  defp action_status("decision", data), do: map_value(data, :cycle_status, "recorded")
  defp action_status("manual_publish", _data), do: "published"
  defp action_status(_type, data), do: map_value(data, :result, "recorded")

  defp action_detail("decision", data) do
    map_value(data, :model_reason) || map_value(data, :candidate_id) || "Decision recorded."
  end

  defp action_detail("manual_publish", data) do
    map_value(data, :record_uri) || map_value(data, :event_key) || "Draft published."
  end

  defp action_detail(_type, data) do
    map_value(data, :record_uri) || map_value(data, :rkey) || map_value(data, :collection) ||
      "Protocol action recorded."
  end

  defp review_attention(items, review, kind) do
    if map_value(review, :status) == :failed do
      items ++
        [
          %{
            key: "#{kind}-review",
            label: "#{humanize(kind)} review needs attention",
            detail: map_value(review, :detail, "Check the Oban job and local logs."),
            state: "attention"
          }
        ]
    else
      items
    end
  end

  defp maybe_add(items, value, item) when value not in [nil, false, ""], do: items ++ [item]
  defp maybe_add(items, _value, _item), do: items

  defp add_count_attention(
         items,
         count,
         key,
         singular,
         plural,
         detail,
         state \\ "attention"
       )

  defp add_count_attention(items, count, key, singular, plural, detail, state)
       when is_integer(count) and count > 0 do
    label = if count == 1, do: "1 #{singular}", else: "#{count} #{plural}"
    items ++ [%{key: key, label: label, detail: detail, state: state}]
  end

  defp add_count_attention(items, _count, _key, _singular, _plural, _detail, _state),
    do: items

  defp migration_attention?(inspection) do
    inspection_value(inspection, [:sqlite, :migrations, :status], "unknown") not in [
      "current",
      :current
    ]
  end

  defp relative_time(next_at, now) do
    seconds = max(DateTime.diff(next_at, now, :second), 0)

    cond do
      seconds < 60 -> "in less than 1 min"
      seconds < 3_600 -> "in #{Integer.ceil_div(seconds, 60)} min"
      seconds < 86_400 -> "in #{Integer.ceil_div(seconds, 3_600)} hr"
      true -> "in #{Integer.ceil_div(seconds, 86_400)} days"
    end
  end

  defp budget_percent(_used, 0), do: 0
  defp budget_percent(used, limit), do: min(round(used / limit * 100), 100)

  defp event_type(event), do: event |> map_value(:type, "") |> to_string()

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp inspection_count(inspection, path, key) do
    inspection |> inspection_value(path, %{}) |> map_value(key, 0) |> non_negative_integer()
  end

  defp inspection_list(inspection, path) do
    case inspection_value(inspection, path, []) do
      list when is_list(list) -> list
      _value -> []
    end
  end

  defp inspection_value(value, [], _default), do: value

  defp inspection_value(value, [key | rest], default) when is_map(value) do
    value
    |> map_value(key, default)
    |> inspection_value(rest, default)
  end

  defp inspection_value(_value, _path, default), do: default

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value), do: 0

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
