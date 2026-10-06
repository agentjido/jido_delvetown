defmodule JidoDelvetown.Storage.ActorRelationship do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:actor_did, :string, autogenerate: false}
  schema "actor_relationships" do
    field(:friend, :boolean, default: false)
    field(:follows_agent, :string, default: "unknown")
    field(:agent_follows, :string, default: "unknown")
    field(:topics, :map, default: %{})
    field(:notes, :string)
    field(:do_not_mention, :boolean, default: false)
    field(:friend_since, :utc_datetime_usec)
    field(:first_related_at, :utc_datetime_usec)
    field(:last_related_at, :utc_datetime_usec)
    field(:last_referenced_at, :utc_datetime_usec)
    field(:reference_count, :integer, default: 0)
    field(:metadata, :map, default: %{})
    timestamps(type: :utc_datetime_usec)
  end
end
