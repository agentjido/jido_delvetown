defmodule JidoDelvetownWeb.DashboardInboxTest do
  use ExUnit.Case, async: true

  alias JidoDelvetownWeb.DashboardInbox

  test "builds category, proposal, action, and scan summaries" do
    inspection = %{
      events: %{
        recent: [
          %{event_key: "reply:1", kind: "reply", state: "pending", proposal: %{action: "reply"}},
          %{event_key: "mention:1", kind: "mention", state: "completed", proposal: nil},
          %{event_key: "like:1", kind: "like", state: "failed", proposal: nil}
        ]
      },
      scans: [
        %{
          name: "notifications",
          last_completed_at: "2026-10-06T12:00:00Z",
          lease_active?: false
        }
      ]
    }

    inbox = DashboardInbox.build(inspection)

    assert inbox.actionable_count == 2
    assert inbox.proposal_count == 1

    assert Enum.map(inbox.categories, &{&1.key, &1.count}) == [
             {"reply", 1},
             {"mention", 1},
             {"follow", 0},
             {"like", 1}
           ]

    assert inbox.last_scan.last_completed_at == "2026-10-06T12:00:00Z"
  end

  test "returns a safe empty inbox when inspection is unavailable" do
    inbox = DashboardInbox.build(%{})

    assert inbox.events == []
    assert inbox.actionable_count == 0
    assert inbox.proposal_count == 0
    assert Enum.all?(inbox.categories, &(&1.count == 0))
    assert inbox.last_scan == nil
  end
end
