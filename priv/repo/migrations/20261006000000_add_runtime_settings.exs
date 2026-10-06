defmodule JidoDelvetown.Repo.Migrations.AddRuntimeSettings do
  use Ecto.Migration

  def up do
    create table(:runtime_settings, primary_key: false) do
      add(:scope, :string, primary_key: true)

      add(:schema_version, :integer,
        null: false,
        check: %{
          name: "runtime_settings_schema_version_positive",
          expr: "schema_version > 0"
        }
      )

      add(:version, :integer,
        null: false,
        default: 1,
        check: %{name: "runtime_settings_version_positive", expr: "version > 0"}
      )

      add(:values, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create table(:runtime_settings_revisions) do
      add(
        :settings_scope,
        references(:runtime_settings,
          column: :scope,
          type: :string,
          on_delete: :restrict
        ),
        null: false
      )

      add(:version, :integer,
        null: false,
        check: %{name: "runtime_settings_revisions_version_positive", expr: "version > 0"}
      )

      add(:schema_version, :integer,
        null: false,
        check: %{
          name: "runtime_settings_revisions_schema_version_positive",
          expr: "schema_version > 0"
        }
      )

      add(:values, :map, null: false, default: %{})
      add(:source, :string, null: false)
      add(:metadata, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:runtime_settings_revisions, [:settings_scope, :version]))

    create(index(:runtime_settings_revisions, [:settings_scope, :inserted_at]))

    execute("""
    CREATE TRIGGER runtime_settings_revisions_no_update
    BEFORE UPDATE ON runtime_settings_revisions
    BEGIN
      SELECT RAISE(ABORT, 'runtime settings revisions are immutable');
    END
    """)

    execute("""
    CREATE TRIGGER runtime_settings_revisions_no_delete
    BEFORE DELETE ON runtime_settings_revisions
    BEGIN
      SELECT RAISE(ABORT, 'runtime settings revisions are immutable');
    END
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS runtime_settings_revisions_no_delete")
    execute("DROP TRIGGER IF EXISTS runtime_settings_revisions_no_update")
    drop(table(:runtime_settings_revisions))
    drop(table(:runtime_settings))
  end
end
