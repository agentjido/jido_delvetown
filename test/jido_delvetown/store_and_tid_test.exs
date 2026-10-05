defmodule JidoDelvetown.StoreAndTidTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Config
  alias JidoDelvetown.Store
  alias JidoDelvetown.Tid

  test "TIDs have the AT Protocol alphabet and increase" do
    first = Tid.generate()
    second = Tid.generate()

    assert String.length(first) == 13
    assert first =~ ~r/\A[234567abcdefghijklmnopqrstuvwxyz]{13}\z/
    assert first < second
  end

  test "the Store returns one record key for one effect key" do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_delvetown_store_#{System.unique_integer([:positive])}.dets"
      )

    name = JidoDelvetown.StoreTestServer
    table = JidoDelvetown.StoreTestTable

    start_supervised!(
      Supervisor.child_spec({Store, name: name, table: table, path: path}, id: make_ref())
    )

    on_exit(fn -> File.rm(path) end)

    assert {:ok, first} = Store.reserve_effect("same", "town.delve.feed.like", name)
    assert {:ok, second} = Store.reserve_effect("same", "town.delve.feed.like", name)
    assert first.rkey == second.rkey

    assert {:ok, complete} = Store.complete_effect("same", %{uri: "at://receipt"}, name)
    assert complete.status == :complete
    assert Store.counts(name) == %{reserved: 0, complete: 1, seen: 0}
  end

  test "one configurable directory contains both local stores" do
    previous = System.get_env("DELVETOWN_DATA_DIR")
    data_dir = Path.join(System.tmp_dir!(), "jido_delvetown_data")
    System.put_env("DELVETOWN_DATA_DIR", data_dir)

    on_exit(fn -> restore_env("DELVETOWN_DATA_DIR", previous) end)

    assert Config.data_dir() == data_dir
    assert Config.checkpoint_path() == Path.join(data_dir, "jido_checkpoints")
    assert Config.state_path() == Path.join(data_dir, "delvetown_state.dets")

    assert JidoDelvetown.Jido.__jido_persistence__() ==
             {Jido.Persistence.File, path: Config.checkpoint_path()}
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
