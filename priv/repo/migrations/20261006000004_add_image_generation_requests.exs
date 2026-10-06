defmodule JidoDelvetown.Repo.Migrations.AddImageGenerationRequests do
  use Ecto.Migration

  def change do
    create table(:image_generation_requests, primary_key: false) do
      add :request_key, :string, primary_key: true
      add :request_fingerprint, :string, null: false
      add :provider, :string, null: false
      add :model, :string, null: false
      add :prompt, :text, null: false
      add :options, :map, null: false, default: %{}
      add :request_metadata, :map, null: false, default: %{}
      add :state, :string, null: false, default: "reserved"
      add :attempt_count, :integer, null: false, default: 0
      add :usage, :map
      add :response_metadata, :map
      add :failure, :map

      add :artifact_digest,
          references(:image_artifacts,
            column: :digest,
            type: :string,
            on_delete: :restrict
          )

      add :reserved_at, :utc_datetime_usec, null: false
      add :attempted_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:image_generation_requests, [:state, :updated_at])
    create index(:image_generation_requests, [:request_fingerprint])
    create index(:image_generation_requests, [:artifact_digest])
  end
end
