defmodule JidoDelvetownWeb.DashboardDraftsTest do
  use ExUnit.Case, async: true

  alias JidoDelvetownWeb.DashboardDrafts

  test "counts draft types and durable review states" do
    drafts =
      DashboardDrafts.build(%{
        simulated_posts: [
          %{event_key: "text:pending", review: %{state: "pending"}},
          %{event_key: "text:published", published_status: "completed"}
        ],
        like_proposals: [
          %{event_key: "like:approved", review: %{state: "approved"}},
          %{
            event_key: "like:published",
            publication_state: "published",
            review: %{state: "approved"}
          }
        ],
        image_drafts: [
          %{draft_key: "image:rejected", review: %{state: "rejected"}}
        ]
      })

    assert drafts == %{
             total_count: 5,
             pending_count: 1,
             approved_count: 1,
             rejected_count: 1,
             published_count: 2,
             type_counts: %{text: 2, like: 2, image: 1}
           }
  end

  test "uses pending as the safe state for old inspection data" do
    drafts = DashboardDrafts.build(%{simulated_posts: [%{}]})

    assert drafts.total_count == 1
    assert drafts.pending_count == 1
    assert drafts.approved_count == 0
  end
end
