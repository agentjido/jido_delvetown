defmodule JidoDelvetown.Storage.Conversation do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:root_uri, :string, autogenerate: false}
  schema "conversations" do
    field(:actor_did, :string)
    field(:turn_count, :integer, default: 0)
    field(:last_record_uri, :string)
    field(:last_action, :string)
    field(:last_action_at, :utc_datetime_usec)
    field(:status, :string, default: "active")
    field(:metadata, :map, default: %{})
    timestamps(type: :utc_datetime_usec)
  end
end
