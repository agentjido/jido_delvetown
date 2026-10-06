defmodule JidoDelvetown.Repo.Migrations.AddImageDrafts do
  use Ecto.Migration

  def change do
    create table(:image_artifacts, primary_key: false) do
      add :digest, :string, primary_key: true
      add :bytes, :binary, null: false
      add :mime_type, :string, null: false
      add :byte_size, :integer, null: false
      add :width, :integer
      add :height, :integer
      add :source_metadata, :map, null: false, default: %{}
      add :state, :string, null: false, default: "staged"
      add :failure, :map
      timestamps(type: :utc_datetime_usec)
    end

    create index(:image_artifacts, [:state, :updated_at])

    create table(:image_drafts, primary_key: false) do
      add :draft_key, :string, primary_key: true

      add :artifact_digest,
          references(:image_artifacts,
            column: :digest,
            type: :string,
            on_delete: :restrict
          ),
          null: false

      add :caption, :text, null: false
      add :alt_text, :text, null: false
      add :state, :string, null: false, default: "staged"
      add :failure, :map
      timestamps(type: :utc_datetime_usec)
    end

    create index(:image_drafts, [:artifact_digest])
    create index(:image_drafts, [:state, :updated_at])
  end
end
