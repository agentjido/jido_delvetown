defmodule JidoDelvetown.Storage.ImageDraft do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:draft_key, :string, autogenerate: false}
  schema "image_drafts" do
    field(:artifact_digest, :string)
    field(:caption, :string)
    field(:alt_text, :string)
    field(:state, :string, default: "staged")
    field(:failure, :map)
    field(:post_effect_key, :string)
    field(:post_record, :map)
    field(:post_receipt, :map)
    field(:publish_started_at, :utc_datetime_usec)
    field(:published_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
