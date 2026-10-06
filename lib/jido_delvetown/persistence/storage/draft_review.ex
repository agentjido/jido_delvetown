defmodule JidoDelvetown.Storage.DraftReview do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:review_key, :string, autogenerate: false}
  schema "draft_reviews" do
    field(:kind, :string)
    field(:source_key, :string)
    field(:decision, :string)
    field(:reviewed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
