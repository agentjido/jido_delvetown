defmodule JidoDelvetown.SettingsStorageTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings.Contract
  alias JidoDelvetown.Storage.{Settings, SettingsRevision}

  test "stores one typed active configuration with schema and lock versions" do
    scope = unique_scope()

    settings =
      %Settings{}
      |> Settings.changeset(%{
        scope: scope,
        schema_version: Contract.schema_version(),
        values: %{"autonomy_mode" => "observe"}
      })
      |> Repo.insert!()

    assert settings.scope == scope
    assert settings.schema_version == Contract.schema_version()
    assert settings.version == 1
    assert settings.values == %{"autonomy_mode" => "observe"}
  end

  test "rejects a stale active configuration update" do
    scope = unique_scope()

    original =
      %Settings{}
      |> Settings.changeset(%{
        scope: scope,
        schema_version: Contract.schema_version(),
        values: %{"autonomy_mode" => "observe"}
      })
      |> Repo.insert!()

    first_reader = Repo.get!(Settings, scope)
    stale_reader = Repo.get!(Settings, scope)

    updated =
      first_reader
      |> Settings.changeset(%{
        scope: "must-not-change",
        values: %{"autonomy_mode" => "review"}
      })
      |> Repo.update!()

    assert updated.scope == scope
    assert updated.version == original.version + 1
    assert updated.values == %{"autonomy_mode" => "review"}

    assert_raise Ecto.StaleEntryError, fn ->
      stale_reader
      |> Settings.changeset(%{values: %{"autonomy_mode" => "autonomous"}})
      |> Repo.update!()
    end
  end

  test "stores one revision for each configuration version" do
    settings = insert_settings()

    first =
      insert_revision(settings, %{
        version: 1,
        source: "bootstrap",
        metadata: %{"reason" => "safe defaults"}
      })

    assert first.settings_scope == settings.scope
    assert first.schema_version == Contract.schema_version()
    assert first.values == settings.values

    duplicate =
      %SettingsRevision{}
      |> SettingsRevision.insert_changeset(%{
        settings_scope: settings.scope,
        version: 1,
        schema_version: Contract.schema_version(),
        values: settings.values,
        source: "operator"
      })
      |> Repo.insert()

    assert {:error, changeset} = duplicate
    assert "has already been taken" in errors_on(changeset).version
  end

  test "database triggers reject revision updates and deletes" do
    settings = insert_settings()
    revision = insert_revision(settings, %{version: 1, source: "bootstrap"})

    assert {:error, update_error} =
             Ecto.Adapters.SQL.query(
               Repo,
               "UPDATE runtime_settings_revisions SET source = ? WHERE id = ?",
               ["changed", revision.id]
             )

    assert Exception.message(update_error) =~ "runtime settings revisions are immutable"

    assert {:error, delete_error} =
             Ecto.Adapters.SQL.query(
               Repo,
               "DELETE FROM runtime_settings_revisions WHERE id = ?",
               [revision.id]
             )

    assert Exception.message(delete_error) =~ "runtime settings revisions are immutable"
    assert Repo.get!(SettingsRevision, revision.id).source == "bootstrap"
  end

  test "revision validation requires positive schema and configuration versions" do
    changeset =
      SettingsRevision.insert_changeset(%SettingsRevision{}, %{
        settings_scope: unique_scope(),
        version: 0,
        schema_version: 0,
        values: %{},
        source: "test"
      })

    refute changeset.valid?
    assert "must be greater than 0" in errors_on(changeset).version
    assert "must be greater than 0" in errors_on(changeset).schema_version
  end

  defp insert_settings do
    %Settings{}
    |> Settings.changeset(%{
      scope: unique_scope(),
      schema_version: Contract.schema_version(),
      values: %{"autonomy_mode" => "observe"}
    })
    |> Repo.insert!()
  end

  defp insert_revision(settings, attributes) do
    attributes =
      Map.merge(
        %{
          settings_scope: settings.scope,
          schema_version: settings.schema_version,
          values: settings.values,
          metadata: %{}
        },
        attributes
      )

    %SettingsRevision{}
    |> SettingsRevision.insert_changeset(attributes)
    |> Repo.insert!()
  end

  defp unique_scope,
    do: "test-#{System.unique_integer([:positive, :monotonic])}"

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
