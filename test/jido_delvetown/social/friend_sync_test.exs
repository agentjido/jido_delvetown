defmodule JidoDelvetown.FriendSyncTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{FriendList, FriendSync, Repo}
  alias JidoDelvetown.Storage.{Actor, ActorRelationship}
  alias JidoDelvetown.Test.RuntimeSettings

  defmodule FakeSource do
    def list_own_records(collection, params) do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), {
        :list_own_records,
        collection,
        params
      })

      cursor = Map.get(params, :cursor)
      Application.fetch_env!(:jido_delvetown, :friend_sync_pages) |> Map.fetch!(cursor)
    end

    def query(method, %{actor: actor}) do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), {:profile, method, actor})

      Application.fetch_env!(:jido_delvetown, :friend_sync_profiles)
      |> Map.get(actor, {:error, :not_found})
    end
  end

  setup do
    Repo.delete_all(ActorRelationship)
    Repo.delete_all(Actor)

    previous = %{
      test_owner: Application.get_env(:jido_delvetown, :test_owner),
      friend_sync_pages: Application.get_env(:jido_delvetown, :friend_sync_pages),
      friend_sync_profiles: Application.get_env(:jido_delvetown, :friend_sync_profiles)
    }

    Application.put_env(:jido_delvetown, :test_owner, self())
    Application.put_env(:jido_delvetown, :friend_sync_profiles, %{})
    restore_settings = RuntimeSettings.preserve!(friend_sync_limit: 1_000)

    on_exit(fn ->
      restore_env(previous)
      restore_settings.()
    end)

    :ok
  end

  test "paginates the follow collection and saves friends by DID" do
    Application.put_env(:jido_delvetown, :friend_sync_pages, %{
      nil => {:ok, %{"records" => [follow("did:plc:one")], "cursor" => "next"}},
      "next" => {:ok, %{records: [follow("did:plc:two")]}}
    })

    Application.put_env(:jido_delvetown, :friend_sync_profiles, %{
      "did:plc:one" =>
        {:ok, %{"did" => "did:plc:one", "handle" => "one.test", "displayName" => "One"}},
      "did:plc:two" =>
        {:ok,
         %{
           profile: %{did: "did:plc:two", handle: "two.test", display_name: "Two"}
         }}
    })

    assert {:ok, %{seen: 2, added: 2, removed: 0, pages: 2, records: 2, profile_errors: 0}} =
             FriendSync.sync(source: FakeSource)

    assert Enum.map(FriendList.list(), & &1.did) == ["did:plc:one", "did:plc:two"]
    assert FriendList.get("did:plc:one").display_name == "One"
    assert FriendList.get("did:plc:two").agent_follows == "yes"

    assert_received {:list_own_records, "town.delve.graph.follow", %{limit: 100, reverse: true}}

    assert_received {:list_own_records, "town.delve.graph.follow",
                     %{cursor: "next", limit: 100, reverse: true}}

    assert_received {:profile, "town.delve.actor.getProfile", "did:plc:one"}
    assert_received {:profile, "town.delve.actor.getProfile", "did:plc:two"}

    assert {:ok, %{added: 0, removed: 0, seen: 2}} =
             FriendSync.sync(source: FakeSource)

    assert length(FriendList.list()) == 2
  end

  test "removes stale imported friends but keeps a manual friend" do
    configure_one_page([follow("did:plc:manual"), follow("did:plc:remote")])
    assert {:ok, %{added: 2}} = FriendSync.sync(source: FakeSource)

    assert {:ok, _friend} =
             FriendList.add(%{did: "did:plc:manual", handle: "manual.test"})

    configure_one_page([])
    assert {:ok, %{removed: 2}} = FriendSync.sync(source: FakeSource)

    assert %{friend: true, agent_follows: "no"} = FriendList.get("did:plc:manual")
    assert FriendList.get("did:plc:remote") == nil

    assert %ActorRelationship{friend: false, agent_follows: "no"} =
             Repo.get(ActorRelationship, "did:plc:remote")

    assert {:ok, %{removed: 0}} = FriendSync.sync(source: FakeSource)
  end

  test "a local exclusion is not overwritten by the next sync" do
    configure_one_page([follow("did:plc:excluded")])
    assert {:ok, _result} = FriendSync.sync(source: FakeSource)
    assert {:ok, %ActorRelationship{friend: false}} = FriendList.remove("did:plc:excluded")

    assert {:ok, %{added: 0, seen: 1}} = FriendSync.sync(source: FakeSource)
    assert FriendList.get("did:plc:excluded") == nil

    assert %ActorRelationship{friend: false, agent_follows: "yes"} =
             Repo.get(ActorRelationship, "did:plc:excluded")
  end

  test "saves a DID when its profile is temporarily unavailable" do
    configure_one_page([follow("did:plc:no-profile")])

    assert {:ok, %{seen: 1, profile_errors: 1}} = FriendSync.sync(source: FakeSource)
    assert %{did: "did:plc:no-profile", handle: nil} = FriendList.get("did:plc:no-profile")
  end

  test "normalizes blank profile text and keeps the followed DID" do
    configure_one_page([follow("did:plc:followed")])

    Application.put_env(:jido_delvetown, :friend_sync_profiles, %{
      "did:plc:followed" =>
        {:ok, %{did: "did:plc:other", handle: " followed.test ", display_name: ""}}
    })

    assert {:ok, %{seen: 1, added: 1}} = FriendSync.sync(source: FakeSource)

    assert %{did: "did:plc:followed", handle: "followed.test", display_name: nil} =
             FriendList.get("did:plc:followed")
  end

  test "does not reconcile a partial snapshot" do
    Application.put_env(:jido_delvetown, :friend_sync_pages, %{
      nil => {:ok, %{records: [follow("did:plc:one")], cursor: "more"}}
    })

    assert {:error, :friend_sync_limit_exceeded} =
             FriendSync.sync(source: FakeSource, max_records: 1)

    assert FriendList.list() == []
  end

  test "uses the stored friend sync limit by default" do
    RuntimeSettings.update!(friend_sync_limit: 1)

    Application.put_env(:jido_delvetown, :friend_sync_pages, %{
      nil => {:ok, %{records: [follow("did:plc:one")], cursor: "more"}}
    })

    assert {:error, :friend_sync_limit_exceeded} = FriendSync.sync(source: FakeSource)
    assert FriendList.list() == []
  end

  defp configure_one_page(records) do
    Application.put_env(:jido_delvetown, :friend_sync_pages, %{
      nil => {:ok, %{records: records}}
    })
  end

  defp follow(did), do: %{value: %{"subject" => did}}

  defp restore_env(previous) do
    Enum.each(previous, fn
      {key, nil} -> Application.delete_env(:jido_delvetown, key)
      {key, value} -> Application.put_env(:jido_delvetown, key, value)
    end)
  end
end
