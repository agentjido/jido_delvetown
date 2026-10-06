defmodule JidoDelvetownWeb.DashboardActivityTest do
  use ExUnit.Case, async: true

  alias JidoDelvetownWeb.DashboardActivity

  test "builds one newest-first timeline with category and failure filters" do
    workflow_events = [
      %{
        sequence: 4,
        type: :decision,
        at: "2026-10-06T12:00:00Z",
        data: %{
          action: "reply",
          cycle_status: "proposed",
          model_reason: "Direct technical question"
        }
      }
    ]

    inspection = %{
      effects: %{
        completed_receipts: [
          %{
            operation_key: "reply:complete",
            kind: "reply",
            collection: "town.delve.feed.post",
            status: "completed",
            completed_at: "2026-10-06T12:01:00Z",
            receipt: %{
              uri: "at://did:plc:agent/town.delve.feed.post/published",
              cid: "bafy-receipt"
            }
          }
        ],
        attention: [
          %{
            operation_key: "like:uncertain",
            kind: "like",
            status: "uncertain",
            attempt_count: 2,
            reserved_at: "2026-10-06T12:02:00Z"
          }
        ]
      },
      automation: %{
        recent_jobs: [
          %{
            id: 10,
            state: "completed",
            queue: "delvetown",
            worker: "JidoDelvetown.Workers.FriendSyncWorker",
            attempt: 1,
            max_attempts: 3,
            error_count: 0,
            completed_at: "2026-10-06T12:03:00Z"
          },
          %{
            id: 11,
            state: "retryable",
            queue: "delvetown",
            worker: "JidoDelvetown.Workers.ReactiveParticipationWorker",
            attempt: 2,
            max_attempts: 5,
            error_count: 2,
            attempted_at: "2026-10-06T12:04:00Z"
          }
        ]
      }
    }

    settings = %{
      history: [
        %{
          version: 8,
          current?: true,
          source: "Operator save",
          changed: ["Daily reply limit"],
          inserted_at: "2026-10-06T12:05:00Z"
        }
      ]
    }

    activity = DashboardActivity.build(workflow_events, inspection, settings)

    assert activity.counts == %{
             "all" => 6,
             "actions" => 1,
             "publications" => 1,
             "failures" => 2,
             "jobs" => 2,
             "settings" => 1
           }

    assert hd(activity.items).title == "Runtime settings v8"
    assert Enum.at(activity.items, 1).title == "Reactive Participation Worker"

    assert Enum.map(DashboardActivity.filtered_items(activity, "failures"), & &1.id) == [
             "job:11",
             "failure:like:uncertain"
           ]

    assert [publication] = DashboardActivity.filtered_items(activity, "publications")
    assert publication.uri == "at://did:plc:agent/town.delve.feed.post/published"
    assert publication.cid == "bafy-receipt"
  end

  test "normalizes invalid filters and missing data to the full empty timeline" do
    activity = DashboardActivity.build(nil, %{}, %{})

    assert activity.items == []
    assert activity.counts["all"] == 0
    assert DashboardActivity.normalize_filter("unknown") == "all"
    assert DashboardActivity.filtered_items(activity, "unknown") == []
  end
end
