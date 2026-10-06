defmodule JidoDelvetown.ConversationMemoryTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.ConversationMemory
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.Conversation

  setup do
    Repo.delete_all(Conversation)
    :ok
  end

  test "stores reply turns and response context" do
    first = candidate("reply-1")
    second = candidate("reply-2")

    assert :ok =
             ConversationMemory.remember(
               first,
               %{status: "acted"},
               %{action: "reply"},
               "2026-10-05T12:00:00Z"
             )

    assert :ok =
             ConversationMemory.remember(
               second,
               %{status: "simulated"},
               %{action: "reply"},
               "2026-10-05T12:05:00Z"
             )

    assert %Conversation{
             actor_did: "did:plc:member",
             turn_count: 2,
             last_record_uri: "at://did:plc:member/town.delve.feed.post/reply-2",
             last_action: "reply",
             status: "active"
           } = ConversationMemory.get(root_uri())

    assert %{
             turn_count: 2,
             status: "active",
             unanswered_follow_ups: 0,
             last_action_at: "2026-10-05T12:05:00.000000Z"
           } = ConversationMemory.context(root_uri())
  end

  test "closes an existing conversation when policy ends it" do
    assert :ok =
             ConversationMemory.remember(
               candidate("reply-1"),
               %{status: "acted"},
               %{action: "reply"},
               "2026-10-05T12:00:00Z"
             )

    assert :ok =
             ConversationMemory.remember(
               candidate("reply-2"),
               %{reason: "conversation_turn_limit"},
               %{action: "skip"},
               "2026-10-05T12:05:00Z"
             )

    assert %Conversation{turn_count: 1, status: "closed"} =
             ConversationMemory.get(root_uri())
  end

  defp candidate(id) do
    %{
      event_key: "event:#{id}",
      uri: "at://did:plc:member/town.delve.feed.post/#{id}",
      author: %{did: "did:plc:member"},
      root: %{uri: root_uri(), cid: "root-cid"}
    }
  end

  defp root_uri, do: "at://did:plc:root/town.delve.feed.post/root"
end
