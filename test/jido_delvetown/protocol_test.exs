defmodule JidoDelvetown.ProtocolTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Actions.LikePost
  alias JidoDelvetown.Protocol
  alias JidoDelvetown.Store
  alias JidoDelvetown.Test.FakeSession
  alias JidoDelvetown.Test.FakeTransport

  @test_store JidoDelvetown.TestStore
  @test_table JidoDelvetown.TestStoreTable

  setup do
    path =
      Path.join(System.tmp_dir!(), "jido_delvetown_#{System.unique_integer([:positive])}.dets")

    start_supervised!(
      Supervisor.child_spec(
        {Store, name: @test_store, table: @test_table, path: path},
        id: make_ref()
      )
    )

    previous = %{
      session_module: Application.get_env(:jido_delvetown, :session_module),
      transport: Application.get_env(:jido_delvetown, :transport),
      store: Application.get_env(:jido_delvetown, :store),
      test_owner: Application.get_env(:jido_delvetown, :test_owner),
      create_result: Application.get_env(:jido_delvetown, :create_result),
      get_result: Application.get_env(:jido_delvetown, :get_result)
    }

    old_write = System.get_env("DELVETOWN_WRITE_ENABLED")

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :store, @test_store)
    Application.put_env(:jido_delvetown, :test_owner, self())

    on_exit(fn ->
      restore_env(previous)
      restore_system_env("DELVETOWN_WRITE_ENABLED", old_write)
      File.rm(path)
    end)

    :ok
  end

  test "write Actions are disabled by default" do
    System.put_env("DELVETOWN_WRITE_ENABLED", "false")

    assert {:error, :writes_disabled} =
             LikePost.run(%{uri: "at://did:plc:other/town.delve.feed.post/one", cid: "cid"}, %{})

    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "a completed effect reuses its saved receipt" do
    System.put_env("DELVETOWN_WRITE_ENABLED", "true")
    params = %{uri: "at://did:plc:other/town.delve.feed.post/one", cid: "cid"}

    assert {:ok, %{reused?: false}} = LikePost.run(params, %{})
    assert_received {:create_record, "town.delve.feed.like", record, rkey}
    assert record["$type"] == "town.delve.feed.like"
    assert is_binary(rkey)

    assert {:ok, %{reused?: true}} = LikePost.run(params, %{})
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "an uncertain create is reconciled with the fixed record key" do
    System.put_env("DELVETOWN_WRITE_ENABLED", "true")
    Application.put_env(:jido_delvetown, :create_result, {:error, :timeout})

    Application.put_env(
      :jido_delvetown,
      :get_result,
      {:ok, %{uri: "at://reconciled", cid: "cid"}}
    )

    assert {:ok, %{reconciled?: true}} =
             Protocol.create_record("effect-key", "town.delve.feed.like", %{subject: %{}})

    assert_received {:create_record, "town.delve.feed.like", _record, rkey}
    assert_received {:get_record, "town.delve.feed.like", ^rkey}
    assert %{status: :complete, rkey: ^rkey} = Store.effect("effect-key", @test_store)
  end

  test "delete rejects a record owned by another account" do
    System.put_env("DELVETOWN_WRITE_ENABLED", "true")

    assert {:error, :record_not_owned} =
             Protocol.delete_own_record("at://did:plc:other/town.delve.feed.like/record-key")

    refute_received {:delete_record, _collection, _rkey}
  end

  defp restore_env(values) do
    Enum.each(values, fn
      {key, nil} -> Application.delete_env(:jido_delvetown, key)
      {key, value} -> Application.put_env(:jido_delvetown, key, value)
    end)
  end

  defp restore_system_env(name, nil), do: System.delete_env(name)
  defp restore_system_env(name, value), do: System.put_env(name, value)
end
