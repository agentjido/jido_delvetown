defmodule JidoDelvetown.ConfigTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Config

  test "separates the database from migration-only legacy paths" do
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

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
