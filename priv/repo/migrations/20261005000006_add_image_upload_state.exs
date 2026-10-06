defmodule JidoDelvetown.Repo.Migrations.AddImageUploadState do
  use Ecto.Migration

  def change do
    alter table(:image_artifacts) do
      add :upload_attempt_count, :integer, null: false, default: 0
      add :upload_receipt, :map
      add :upload_started_at, :utc_datetime_usec
      add :uploaded_at, :utc_datetime_usec
    end
  end
end
