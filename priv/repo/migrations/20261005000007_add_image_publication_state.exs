defmodule JidoDelvetown.Repo.Migrations.AddImagePublicationState do
  use Ecto.Migration

  def change do
    alter table(:image_drafts) do
      add :post_effect_key, :string
      add :post_record, :map
      add :post_receipt, :map
      add :publish_started_at, :utc_datetime_usec
      add :published_at, :utc_datetime_usec
    end

    create unique_index(:image_drafts, [:post_effect_key])
  end
end
