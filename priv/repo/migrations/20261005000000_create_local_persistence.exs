defmodule JidoDelvetown.Repo.Migrations.CreateLocalPersistence do
  use Ecto.Migration

  def up do
    Jido.Persistence.Ecto.Migration.up(version: 1)

    create table(:scan_state, primary_key: false) do
      add :name, :string, primary_key: true
      add :cursor, :string
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create table(:interaction_events, primary_key: false) do
      add :event_key, :string, primary_key: true
      add :kind, :string, null: false
      add :actor_did, :string
      add :record_uri, :string
      add :source_id, :string
      add :occurred_at, :utc_datetime_usec, null: false
      add :state, :string, null: false
      add :attempt_count, :integer, null: false, default: 0
      add :payload, :map, null: false, default: %{}
      add :failure, :map
      add :claimed_at, :utc_datetime_usec
      add :terminal_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:interaction_events, [:state, :occurred_at])
    create index(:interaction_events, [:actor_did, :occurred_at])
    create index(:interaction_events, [:record_uri])

    create table(:actors, primary_key: false) do
      add :did, :string, primary_key: true
      add :handle, :string
      add :display_name, :string
      add :profile, :map, null: false, default: %{}
      add :first_seen_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :last_interaction_at, :utc_datetime_usec
      add :contact_count, :integer, null: false, default: 0
      add :welcome_status, :string
      add :opted_out, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create index(:actors, [:last_interaction_at])
    create index(:actors, [:welcome_status])

    create table(:conversations, primary_key: false) do
      add :root_uri, :string, primary_key: true
      add :actor_did, :string
      add :turn_count, :integer, null: false, default: 0
      add :last_record_uri, :string
      add :last_action, :string
      add :last_action_at, :utc_datetime_usec
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create index(:conversations, [:actor_did, :last_action_at])
    create index(:conversations, [:status, :last_action_at])

    create table(:effects, primary_key: false) do
      add :operation_key, :string, primary_key: true
      add :kind, :string
      add :collection, :string, null: false
      add :subject_key, :string
      add :actor_did, :string
      add :rkey, :string, null: false
      add :status, :string, null: false
      add :attempt_count, :integer, null: false, default: 0
      add :receipt, :map
      add :failure, :map
      add :reserved_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:effects, [:rkey])
    create index(:effects, [:status, :reserved_at])
    create index(:effects, [:actor_did, :reserved_at])

    create table(:audit_events) do
      add :type, :string, null: false
      add :data, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_events, [:occurred_at])
    create index(:audit_events, [:type, :occurred_at])

    create table(:legacy_imports, primary_key: false) do
      add :name, :string, primary_key: true
      add :checksum, :string, null: false
      add :status, :string, null: false
      add :details, :map, null: false, default: %{}
      add :imported_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end
  end

  def down do
    drop table(:legacy_imports)
    drop table(:audit_events)
    drop table(:effects)
    drop table(:conversations)
    drop table(:actors)
    drop table(:interaction_events)
    drop table(:scan_state)
    Jido.Persistence.Ecto.Migration.down(version: 1)
  end
end
