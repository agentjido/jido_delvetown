defmodule JidoDelvetown.Settings.BootstrapTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings.{Bootstrap, Contract}
  alias JidoDelvetown.Storage.{Settings, SettingsRevision}

  test "seeds safe defaults once" do
    scope = unique_scope()

    assert {:ok, first} = Bootstrap.run(scope: scope)
    assert first.created?
    assert first.scope == scope
    assert first.schema_version == Contract.schema_version()
    assert first.version == 1

    assert {:ok, second} = Bootstrap.run(scope: scope)
    refute second.created?
    assert second == %{first | created?: false}

    settings = Repo.get!(Settings, scope)
    assert settings.values["autonomy_mode"] == "observe"
    refute settings.values["manual_publish_enabled"]
    refute settings.values["mark_notifications_seen"]
    refute settings.values["dry_run_mark_actioned"]

    assert Repo.aggregate(
             from(revision in SettingsRevision,
               where: revision.settings_scope == ^scope
             ),
             :count
           ) == 1
  end

  test "concurrent bootstrap callers create one active row and one revision" do
    scope = unique_scope()

    results =
      1..10
      |> Task.async_stream(
        fn _index -> Bootstrap.run(scope: scope) end,
        max_concurrency: 10,
        ordered: false
      )
      |> Enum.map(fn {:ok, {:ok, result}} -> result end)

    assert Enum.count(results, & &1.created?) == 1

    assert Repo.aggregate(from(settings in Settings, where: settings.scope == ^scope), :count) ==
             1

    assert Repo.aggregate(
             from(revision in SettingsRevision,
               where: revision.settings_scope == ^scope
             ),
             :count
           ) == 1
  end

  test "rejects an unknown stored schema version" do
    scope = unique_scope()

    %Settings{}
    |> Settings.changeset(%{
      scope: scope,
      schema_version: Contract.schema_version() + 1,
      values: %{}
    })
    |> Repo.insert!()

    assert {:error, {:unsupported_settings_schema, stored_version, current_version}} =
             Bootstrap.run(scope: scope)

    assert stored_version == Contract.schema_version() + 1
    assert current_version == Contract.schema_version()
  end

  defp unique_scope,
    do: "bootstrap-test-#{System.unique_integer([:positive, :monotonic])}"
end
