defmodule JidoDelvetown.Storage.InteractionEvent do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:event_key, :string, autogenerate: false}
  schema "interaction_events" do
    field(:kind, :string)
    field(:actor_did, :string)
    field(:record_uri, :string)
    field(:source_id, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:state, :string)
    field(:attempt_count, :integer, default: 0)
    field(:payload, :map, default: %{})
    field(:failure, :map)
    field(:claimed_at, :utc_datetime_usec)
    field(:terminal_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
