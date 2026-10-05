defmodule JidoDelvetown.Storage.Actor do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:did, :string, autogenerate: false}
  schema "actors" do
    field(:handle, :string)
    field(:display_name, :string)
    field(:profile, :map, default: %{})
    field(:first_seen_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:last_interaction_at, :utc_datetime_usec)
    field(:contact_count, :integer, default: 0)
    field(:welcome_status, :string)
    field(:opted_out, :boolean, default: false)
    field(:metadata, :map, default: %{})
    timestamps(type: :utc_datetime_usec)
  end
end
