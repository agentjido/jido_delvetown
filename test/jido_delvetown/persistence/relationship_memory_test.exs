defmodule JidoDelvetown.RelationshipMemoryTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{FriendList, RelationshipMemory, Repo}
  alias JidoDelvetown.Storage.{Actor, ActorRelationship}

  setup do
    Repo.delete_all(ActorRelationship)
    Repo.delete_all(Actor)
    :ok
  end

  test "records that an actor follows the agent" do
    candidate = %{
      reason: "follow",
      author: %{did: "did:plc:follower", handle: "follower.test"}
    }

    assert :ok =
             RelationshipMemory.remember(
               candidate,
               %{status: "ignored"},
               %{action: "skip"},
               "2026-10-05T12:00:00Z"
             )

    assert %ActorRelationship{follows_agent: "yes"} =
             Repo.get(ActorRelationship, "did:plc:follower")
  end

  test "records friend references from completed response text" do
    assert {:ok, friend} =
             FriendList.add(%{did: "did:plc:friend", handle: "friend.delve.town"})

    assert :ok =
             RelationshipMemory.remember(
               %{reason: "reply"},
               %{status: "simulated"},
               %{action: "reply", text: "Ask @friend.delve.town about OTP."},
               "2026-10-05T12:00:00Z"
             )

    assert FriendList.get(friend.did).reference_count == 1
  end

  test "does not record friend references for a failed cycle" do
    assert {:ok, friend} =
             FriendList.add(%{did: "did:plc:friend", handle: "friend.delve.town"})

    assert :ok =
             RelationshipMemory.remember(
               %{reason: "reply"},
               %{status: "failed"},
               %{action: "reply", text: "Ask @friend.delve.town about OTP."},
               "2026-10-05T12:00:00Z"
             )

    assert FriendList.get(friend.did).reference_count == 0
  end
end
