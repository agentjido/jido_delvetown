defmodule JidoDelvetown.Repo.Migrations.RecordActionSettings do
  use Ecto.Migration

  def change do
    alter table(:effects) do
      add(:settings, :map)
    end

    alter table(:image_drafts) do
      add(:publication_settings, :map)
    end
  end
end
