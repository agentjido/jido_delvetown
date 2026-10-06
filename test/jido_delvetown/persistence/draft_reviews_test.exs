defmodule JidoDelvetown.DraftReviewsTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{DraftReviews, ImageDrafts, InteractionEvents, Repo}
  alias JidoDelvetown.Storage.{DraftReview, ImageArtifact, ImageDraft, InteractionEvent}

  @image_bytes <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "review">>

  setup do
    clear_records()
    on_exit(&clear_records/0)
    :ok
  end

  test "stores one idempotent decision and permits an operator correction" do
    event_key = simulated_event("text:review", "reply")

    assert {:ok, first} = DraftReviews.decide("text", event_key, "approved")
    assert first.decision == "approved"
    assert DraftReviews.approved?("text", event_key)

    assert {:ok, repeated} = DraftReviews.decide("text", event_key, "approved")
    assert repeated.review_key == first.review_key
    assert Repo.aggregate(DraftReview, :count, :review_key) == 1

    assert {:ok, corrected} = DraftReviews.decide("text", event_key, "rejected")
    assert corrected.review_key == first.review_key
    assert corrected.decision == "rejected"
    refute DraftReviews.approved?("text", event_key)
    assert Repo.aggregate(DraftReview, :count, :review_key) == 1
  end

  test "reviews simulated likes and staged images with the same contract" do
    like_key = simulated_event("like:review", "like")

    assert {:ok, like_review} = DraftReviews.decide("like", like_key, "approved")
    assert like_review.kind == "like"

    assert {:ok, staged} =
             ImageDrafts.stage("image:review", @image_bytes, %{
               caption: "AgentJido reviews a local image.",
               alt_text: "A green robot checks an image preview.",
               mime_type: "image/png",
               width: 640,
               height: 480
             })

    assert {:ok, image_review} =
             DraftReviews.decide("image", staged.draft.key, "rejected")

    assert image_review.kind == "image"

    decisions = DraftReviews.decisions()
    assert decisions[{"like", like_key}].state == "approved"
    assert decisions[{"image", staged.draft.key}].state == "rejected"
  end

  test "rejects missing, terminal, mismatched, and invalid review targets" do
    pending_key = "text:pending"

    assert {:ok, _event} =
             InteractionEvents.observe(%{
               event_key: pending_key,
               kind: "reply",
               payload: %{action: "reply", cycle_status: "simulated"}
             })

    assert {:error, :not_reviewable} =
             DraftReviews.decide("text", pending_key, "approved")

    like_key = simulated_event("like:mismatch", "like")

    assert {:error, :draft_kind_mismatch} =
             DraftReviews.decide("text", like_key, "approved")

    assert {:error, :not_found} = DraftReviews.decide("image", "missing", "approved")
    assert {:error, :invalid_draft_kind} = DraftReviews.decide("video", like_key, "approved")

    assert {:error, :invalid_review_decision} =
             DraftReviews.decide("like", like_key, "maybe")
  end

  defp simulated_event(event_key, action) do
    assert {:ok, _event} =
             InteractionEvents.observe(%{
               event_key: event_key,
               kind: action,
               payload: %{action: action, cycle_status: "simulated", text: "Local draft"}
             })

    assert {:ok, _event} = InteractionEvents.claim(event_key)
    assert {:ok, _event} = InteractionEvents.finish(event_key, :completed)
    event_key
  end

  defp clear_records do
    Repo.delete_all(DraftReview)
    Repo.delete_all(InteractionEvent)
    Repo.delete_all(ImageDraft)
    Repo.delete_all(ImageArtifact)
  end
end
