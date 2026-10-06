defmodule JidoDelvetown.Storage.ImageGenerationRequest do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:request_key, :string, autogenerate: false}
  schema "image_generation_requests" do
    field(:request_fingerprint, :string)
    field(:provider, :string)
    field(:model, :string)
    field(:prompt, :string)
    field(:options, :map, default: %{})
    field(:request_metadata, :map, default: %{})
    field(:state, :string, default: "reserved")
    field(:attempt_count, :integer, default: 0)
    field(:usage, :map)
    field(:response_metadata, :map)
    field(:failure, :map)
    field(:artifact_digest, :string)
    field(:reserved_at, :utc_datetime_usec)
    field(:attempted_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
