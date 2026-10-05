defmodule JidoDelvetown.Storage.LegacyImport do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:name, :string, autogenerate: false}
  schema "legacy_imports" do
    field(:checksum, :string)
    field(:status, :string)
    field(:details, :map, default: %{})
    field(:imported_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
