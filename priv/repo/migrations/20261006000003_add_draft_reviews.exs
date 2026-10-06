defmodule JidoDelvetown.Repo.Migrations.AddDraftReviews do
  use Ecto.Migration

  def change do
    create table(:draft_reviews, primary_key: false) do
      add(:review_key, :string, primary_key: true)

      add(:kind, :string,
        null: false,
        check: %{name: "draft_reviews_kind_valid", expr: "kind IN ('text', 'like', 'image')"}
      )

      add(:source_key, :string, null: false)

      add(:decision, :string,
        null: false,
        check: %{
          name: "draft_reviews_decision_valid",
          expr: "decision IN ('approved', 'rejected')"
        }
      )

      add(:reviewed_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:draft_reviews, [:kind, :source_key]))
    create(index(:draft_reviews, [:decision, :reviewed_at]))
  end
end
