defmodule JidoDelvetown.Storage.AuditEvent do
  @moduledoc false

  use Ecto.Schema

  schema "audit_events" do
    field(:type, :string)
    field(:data, :map, default: %{})
    field(:occurred_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
