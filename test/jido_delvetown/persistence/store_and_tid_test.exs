defmodule JidoDelvetown.StoreAndTidTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Config
  alias JidoDelvetown.Store
  alias JidoDelvetown.Storage.{Effect, InteractionEvent, ScanState}
  alias JidoDelvetown.Tid

  setup do
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
    assert complete.status == :completed

    assert Store.counts(name) == %{
             reserved: 0,
             uncertain: 0,
             completed: 1,
             permanent_failure: 0,
             seen: 0
           }
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
    assert Config.legacy_checkpoint_path() == Path.join(data_dir, "jido_checkpoints")
    assert Config.legacy_state_path() == Path.join(data_dir, "delvetown_state.dets")

    assert JidoDelvetown.Jido.__jido_persistence__() ==
             {Jido.Persistence.Ecto, repo: JidoDelvetown.Repo}
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

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
