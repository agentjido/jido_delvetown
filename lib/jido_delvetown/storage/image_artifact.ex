defmodule JidoDelvetown.Storage.ImageArtifact do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:digest, :string, autogenerate: false}
  schema "image_artifacts" do
    field(:bytes, :binary)
    field(:mime_type, :string)
    field(:byte_size, :integer)
    field(:width, :integer)
    field(:height, :integer)
    field(:source_metadata, :map, default: %{})
    field(:state, :string, default: "staged")
    field(:failure, :map)
    field(:upload_attempt_count, :integer, default: 0)
    field(:upload_receipt, :map)
    field(:upload_started_at, :utc_datetime_usec)
    field(:uploaded_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
