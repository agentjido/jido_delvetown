defmodule JidoDelvetown.StoreAndTidTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Config
  alias JidoDelvetown.Store
  alias JidoDelvetown.Storage.{AuditEvent, Effect, InteractionEvent, ScanState}
  alias JidoDelvetown.Tid

  setup do
    Repo.delete_all(AuditEvent)
    Repo.delete_all(Effect)
    Repo.delete_all(InteractionEvent)
    Repo.delete_all(ScanState)
    :ok
  end

  test "TIDs have the AT Protocol alphabet and increase" do
    first = Tid.generate()
    second = Tid.generate()

    assert String.length(first) == 13
    assert first =~ ~r/\A[234567abcdefghijklmnopqrstuvwxyz]{13}\z/
    assert first < second
  end

  test "the Store returns one record key for one effect key" do
    name = JidoDelvetown.StoreTestServer

    start_supervised!(Supervisor.child_spec({Store, name: name}, id: make_ref()))

    assert {:ok, first} = Store.reserve_effect("same", "town.delve.feed.like", name)
    assert {:ok, second} = Store.reserve_effect("same", "town.delve.feed.like", name)
    assert first.rkey == second.rkey

    assert {:ok, complete} = Store.complete_effect("same", %{uri: "at://receipt"}, name)
    assert complete.status == :complete
    assert Store.counts(name) == %{reserved: 0, complete: 1, seen: 0}
  end

  test "configuration separates the database from migration-only legacy paths" do
    previous_data_dir = System.get_env("DELVETOWN_DATA_DIR")
    previous_database = System.get_env("DELVETOWN_DATABASE_PATH")
    data_dir = Path.join(System.tmp_dir!(), "jido_delvetown_data")
    database_path = Path.join(data_dir, "runtime.sqlite3")
    System.put_env("DELVETOWN_DATA_DIR", data_dir)
    System.put_env("DELVETOWN_DATABASE_PATH", database_path)

    on_exit(fn ->
      restore_env("DELVETOWN_DATA_DIR", previous_data_dir)
      restore_env("DELVETOWN_DATABASE_PATH", previous_database)
    end)

    assert Config.data_dir() == data_dir
    assert Config.database_path() == database_path
    assert Config.checkpoint_path() == Path.join(data_dir, "jido_checkpoints")
    assert Config.legacy_state_path() == Path.join(data_dir, "delvetown_state.dets")

    assert JidoDelvetown.Jido.__jido_persistence__() ==
             {Jido.Persistence.File, path: Config.checkpoint_path()}
  end

  test "event sequence continues after the Store restarts" do
    name = JidoDelvetown.EventStoreTestServer

    {:ok, first_store} = Store.start_link(name: name)
    Process.unlink(first_store)
    assert :ok = Store.add_event(:first, %{}, name)
    GenServer.stop(first_store)

    {:ok, second_store} = Store.start_link(name: name)
    Process.unlink(second_store)
    assert :ok = Store.add_event(:second, %{}, name)

    assert [
             %{type: :second, sequence: second_sequence},
             %{type: :first, sequence: first_sequence}
           ] = Store.recent_events(name, 2)

    assert second_sequence == first_sequence + 1
    GenServer.stop(second_store)
  end

  test "concurrent reservations keep one effect and one record key" do
    name = JidoDelvetown.ConcurrentStoreTestServer

    start_supervised!(Supervisor.child_spec({Store, name: name}, id: make_ref()))

    effects =
      1..20
      |> Task.async_stream(
        fn _index -> Store.reserve_effect("concurrent", "town.delve.feed.like", name) end,
        max_concurrency: 20
      )
      |> Enum.map(fn {:ok, {:ok, effect}} -> effect end)

    assert effects |> Enum.map(& &1.rkey) |> Enum.uniq() |> length() == 1
    assert Repo.aggregate(Effect, :count, :operation_key) == 1
  end

  test "cursor and seen state remain after a Store restart" do
    name = JidoDelvetown.ProgressStoreTestServer
    {:ok, first_store} = Store.start_link(name: name)
    Process.unlink(first_store)

    assert :ok = Store.put_cursor("cursor-2", name)
    assert :ok = Store.mark_seen("at://post/one", name)
    GenServer.stop(first_store)

    {:ok, second_store} = Store.start_link(name: name)
    Process.unlink(second_store)
    assert Store.cursor(name) == "cursor-2"
    assert Store.seen?("at://post/one", name)
    assert Store.counts(name).seen == 1
    GenServer.stop(second_store)
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
