defmodule JidoDelvetown.ConversationPolicyTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.ConversationPolicy
  alias JidoDelvetown.Test.RuntimeSettings

  setup do
    restore =
      RuntimeSettings.preserve!(%{
        conversation_turn_limit: 4,
        conversation_max_age_hours: 72,
        conversation_non_response_limit: 2
      })

    on_exit(restore)
  end

  test "continues a useful new turn" do
    assert :continue =
             ConversationPolicy.evaluate(candidate("How should the supervisor restart it?"),
               now: now()
             )
  end

  test "stops a duplicate or low-information turn" do
    duplicate = candidate("One more detail about supervision.")
    duplicate = put_in(duplicate, [:memory, :conversation, :last_record_uri], duplicate.uri)

    assert {:skip, "duplicate_conversation_turn"} =
             ConversationPolicy.evaluate(duplicate, now: now())

    assert {:skip, "conversation_no_new_value"} =
             ConversationPolicy.evaluate(candidate("Thanks."), now: now())
  end

  test "stops a long or old thread" do
    long = put_in(candidate("Can we continue this?"), [:memory, :conversation, :turn_count], 4)

    old =
      put_in(
        candidate("Can we return to this design?"),
        [:memory, :conversation, :last_action_at],
        "2026-10-01T12:00:00Z"
      )

    assert {:skip, "conversation_turn_limit"} =
             ConversationPolicy.evaluate(long, now: now())

    assert {:skip, "conversation_too_old"} =
             ConversationPolicy.evaluate(old, now: now())
  end

  test "stops after the non-response limit or a closed status" do
    unanswered =
      put_in(
        candidate("Here is new information about the failure."),
        [:memory, :conversation, :unanswered_follow_ups],
        2
      )

    closed = put_in(candidate("Can we continue?"), [:memory, :conversation, :status], "closed")

    assert {:skip, "conversation_non_response_limit"} =
             ConversationPolicy.evaluate(unanswered, now: now())

    assert {:skip, "conversation_closed"} =
             ConversationPolicy.evaluate(closed, now: now())
  end

  test "requires useful content but does not require a question" do
    assert ConversationPolicy.useful_turn?("The restart failed after the child timed out.")
    refute ConversationPolicy.useful_turn?("Got it")
    refute ConversationPolicy.useful_turn?("")
  end

  defp candidate(text) do
    %{
      uri: "at://did:plc:member/town.delve.feed.post/new",
      text: text,
      memory: %{
        conversation: %{
          status: "active",
          turn_count: 1,
          last_record_uri: "at://did:plc:member/town.delve.feed.post/old",
          last_action_at: "2026-10-05T11:00:00Z",
          unanswered_follow_ups: 0
        }
      }
    }
  end

  defp now, do: ~U[2026-10-05 12:00:00Z]
end
