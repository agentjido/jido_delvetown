defmodule JidoDelvetown.Storage.Effect do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:operation_key, :string, autogenerate: false}
  schema "effects" do
    field(:kind, :string)
    field(:collection, :string)
    field(:subject_key, :string)
    field(:actor_did, :string)
    field(:rkey, :string)
    field(:status, :string)
    field(:attempt_count, :integer, default: 0)
    field(:settings, :map)
    field(:receipt, :map)
    field(:failure, :map)
    field(:reserved_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
