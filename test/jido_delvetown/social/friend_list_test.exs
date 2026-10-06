defmodule JidoDelvetown.FriendListTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.FriendList
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{Actor, ActorRelationship}

  setup do
    Repo.delete_all(ActorRelationship)
    Repo.delete_all(Actor)
    :ok
  end

  test "adds and updates one friend by stable DID" do
    assert {:ok, friend} =
             FriendList.add(
               %{
                 did: "did:plc:muse",
                 handle: "muse.delve.town",
                 display_name: "Muse"
               },
               topics: ["philosophy", "agents"],
               follows_agent: true,
               notes: "Good fit for identity discussions"
             )

    assert friend.did == "did:plc:muse"
    assert friend.handle == "muse.delve.town"
    assert friend.follows_agent == "yes"
    assert friend.agent_follows == "unknown"
    assert friend.topics == ["agents", "philosophy"]
    assert friend.reference_count == 0

    assert {:ok, updated} =
             FriendList.add(
               %{did: "did:plc:muse", handle: "muse-new.delve.town"},
               agent_follows: :yes
             )

    assert updated.handle == "muse-new.delve.town"
    assert updated.follows_agent == "yes"
    assert updated.agent_follows == "yes"
    assert updated.topics == ["agents", "philosophy"]
    assert [^updated] = FriendList.list()
  end

  test "keeps follower state when a friend is removed" do
    assert {:ok, %ActorRelationship{friend: false, follows_agent: "yes"}} =
             FriendList.record_follows_agent("did:plc:follower")

    assert FriendList.list() == []

    assert {:ok, friend} =
             FriendList.add(%{did: "did:plc:follower", handle: "follower.test"})

    assert friend.follows_agent == "yes"
    assert {:ok, %ActorRelationship{friend: false}} = FriendList.remove(friend.did)
    assert FriendList.get(friend.did) == nil

    assert %ActorRelationship{follows_agent: "yes"} =
             Repo.get(ActorRelationship, friend.did)
  end

  test "gives the decision model a bounded safe friend list" do
    assert {:ok, visible} =
             FriendList.add(
               %{did: "did:plc:visible", handle: "visible.test", display_name: "Visible"},
               topics: ["OTP"],
               notes: "This note stays local"
             )

    assert {:ok, _hidden} =
             FriendList.add(
               %{did: "did:plc:hidden", handle: "hidden.test"},
               do_not_mention: true
             )

    assert [context] = FriendList.for_context()
    assert context.did == visible.did
    assert context.handle == "visible.test"
    assert context.topics == ["OTP"]
    refute Map.has_key?(context, :notes)

    assert :ok = FriendList.record_text_references("Ask @visible.test about supervisors.")
    assert FriendList.get(visible.did).reference_count == 1
    assert :ok = FriendList.record_text_references("This text has no friend tag.")
    assert FriendList.get(visible.did).reference_count == 1
  end

  test "rejects invalid relationship data" do
    assert {:error, {:invalid_relationship_state, :follows_agent}} =
             FriendList.add(%{did: "did:plc:bad"}, follows_agent: "maybe")

    assert {:error, :invalid_topics} =
             FriendList.add(%{did: "did:plc:bad"}, topics: ["valid", 1])

    assert Repo.get(Actor, "did:plc:bad") == nil
  end
end
