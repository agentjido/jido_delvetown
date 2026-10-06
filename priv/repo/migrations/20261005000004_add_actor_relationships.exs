defmodule JidoDelvetown.Repo.Migrations.AddActorRelationships do
  use Ecto.Migration

  def change do
    create table(:actor_relationships, primary_key: false) do
      add :actor_did,
          references(:actors, column: :did, type: :string, on_delete: :delete_all),
          primary_key: true

      add :friend, :boolean, null: false, default: false
      add :follows_agent, :string, null: false, default: "unknown"
      add :agent_follows, :string, null: false, default: "unknown"
      add :topics, :map, null: false, default: %{}
      add :notes, :text
      add :do_not_mention, :boolean, null: false, default: false
      add :friend_since, :utc_datetime_usec
      add :first_related_at, :utc_datetime_usec, null: false
      add :last_related_at, :utc_datetime_usec, null: false
      add :last_referenced_at, :utc_datetime_usec
      add :reference_count, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create index(:actor_relationships, [:friend, :do_not_mention])
    create index(:actor_relationships, [:follows_agent])
    create index(:actor_relationships, [:agent_follows])
    create index(:actor_relationships, [:last_referenced_at])
  end
end
