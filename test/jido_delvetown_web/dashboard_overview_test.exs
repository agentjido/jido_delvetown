defmodule JidoDelvetownWeb.DashboardOverviewTest do
  use ExUnit.Case, async: true

  alias JidoDelvetownWeb.DashboardOverview

  test "builds one focused overview from runtime and SQLite snapshots" do
    status = %{
      autonomy_mode: "review",
      credentials_configured?: true,
      session: %{connected?: true, handle: "agentjido.test"},
      schedule_enabled?: true,
      cron: "*/15 * * * *",
      proactive_review_cron: "5,35 * * * *",
      member_discovery_cron: "7 * * * *",
      friend_sync_cron: "17 * * * *",
      budget: %{replies: 2, posts: 1, welcomes: 0, follows: 1, likes: 3}
    }

    inspection = %{
      events: %{counts: %{"failed" => 1, "pending" => 2}},
      effects: %{attention: [%{operation_key: "reply:uncertain"}]},
      sqlite: %{migrations: %{status: "current"}}
    }

    events = [
      %{
        type: :decision,
        at: "2026-10-06T12:00:00Z",
        data: %{action: "reply", cycle_status: "proposed", model_reason: "Direct question"}
      },
      %{type: :settings_import, at: "2026-10-06T11:00:00Z", data: %{}}
    ]

    limits = %{
      daily_reply_limit: 3,
      daily_post_limit: 1,
      daily_welcome_limit: 2,
      daily_follow_limit: 5,
      daily_like_limit: 5
    }

    overview =
      DashboardOverview.build(status, inspection, events, limits, ~U[2026-10-06 12:00:00Z])

    assert overview.autonomy.label == "Review"
    assert overview.connection.detail == "Signed in as @agentjido.test."

    assert Enum.map(overview.attention, & &1.key) == [
             "effects",
             "failed-events",
             "pending-events"
           ]

    assert Enum.map(overview.schedule.items, & &1.label) == [
             "Timeline review",
             "New-member discovery",
             "Inbox review",
             "Friend sync"
           ]

    assert hd(overview.schedule.items).next_at == ~U[2026-10-06 12:05:00Z]
    assert hd(overview.schedule.items).relative == "in 5 min"

    assert Enum.find(overview.budgets, &(&1.key == "replies")) == %{
             key: "replies",
             label: "Replies and reposts",
             used: 2,
             limit: 3,
             remaining: 1,
             percent: 67
           }

    assert overview.recent_actions == [
             %{
               type: "decision",
               label: "Reply",
               status: "proposed",
               detail: "Direct question",
               at: "2026-10-06T12:00:00Z"
             }
           ]
  end

  test "returns safe fallback states when runtime data is unavailable" do
    overview =
      DashboardOverview.build(%{}, %{}, [], %{}, ~U[2026-10-06 12:00:00Z],
        status_error: :offline,
        reactive_review: %{status: :failed, detail: "Reactive worker stopped."}
      )

    assert overview.autonomy.label == "Unavailable"
    assert overview.connection.label == "Setup required"
    refute overview.schedule.enabled?
    assert overview.schedule.items == []
    assert Enum.all?(overview.budgets, &(&1.limit == 0))
    assert overview.recent_actions == []

    assert Enum.map(overview.attention, & &1.key) == [
             "runtime",
             "credentials",
             "migrations",
             "reactive-review"
           ]
  end
end
