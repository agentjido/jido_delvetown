defmodule JidoDelvetown.DatabaseTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{Config, Repo}

  test "the application starts one migrated SQLite database" do
    assert Process.alive?(Process.whereis(Repo))
    assert File.regular?(Config.database_path())

    tables =
      Repo.query!("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").rows
      |> List.flatten()

    assert "jido_persistence_records" in tables
    assert "scan_state" in tables
    assert "interaction_events" in tables
    assert "actors" in tables
    assert "actor_relationships" in tables
    assert "conversations" in tables
    assert "effects" in tables
    assert "audit_events" in tables
    assert "legacy_imports" in tables
  end

  test "SQLite enforces foreign keys and write-ahead logging" do
    assert [[1]] = Repo.query!("PRAGMA foreign_keys").rows
    assert [[mode]] = Repo.query!("PRAGMA journal_mode").rows
    assert String.downcase(mode) == "wal"
  end

  test "effect operation keys are unique and delete operations can share a record key" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    row = %{
      operation_key: "test:one",
      collection: "town.delve.feed.like",
      rkey: "rkey-one",
      status: "reserved",
      attempt_count: 0,
      reserved_at: now,
      inserted_at: now,
      updated_at: now
    }

    assert {1, nil} = Repo.insert_all("effects", [row])

    assert_raise Exqlite.Error, fn ->
      Repo.insert_all("effects", [%{row | rkey: "rkey-two"}])
    end

    assert {1, nil} = Repo.insert_all("effects", [%{row | operation_key: "delete:test:one"}])

    Repo.query!("DELETE FROM effects WHERE operation_key IN (?, ?)", [
      "test:one",
      "delete:test:one"
    ])
  end

  test "SQLite checkpoint compare-and-swap rejects stale writers" do
    key = "test:checkpoint:#{System.unique_integer([:positive])}"
    opts = [repo: Repo]

    on_exit(fn -> Jido.Persistence.Ecto.delete(key, opts) end)

    assert :ok = Jido.Persistence.Ecto.compare_and_swap(key, :not_found, "one", opts)

    assert {:error, :conflict} =
             Jido.Persistence.Ecto.compare_and_swap(key, :not_found, "x", opts)

    assert :ok = Jido.Persistence.Ecto.compare_and_swap(key, "one", "two", opts)
    assert {:error, :conflict} = Jido.Persistence.Ecto.compare_and_swap(key, "one", "stale", opts)
    assert {:ok, "two"} = Jido.Persistence.Ecto.get(key, opts)
    assert :ok = Jido.Persistence.Ecto.compare_and_swap(key, "two", "two", opts)
  end
end
