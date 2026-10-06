defmodule JidoDelvetown.Storage.ScanState do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:name, :string, autogenerate: false}
  schema "scan_state" do
    field(:cursor, :string)
    field(:metadata, :map, default: %{})
    timestamps(type: :utc_datetime_usec)
  end
end
