defmodule JidoDelvetown.Storage.Settings do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:scope, :string, autogenerate: false}
  schema "runtime_settings" do
    field(:schema_version, :integer)
    field(:version, :integer, default: 1)
    field(:values, :map, default: %{})
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings, attributes) do
    fields =
      if settings.__meta__.state == :loaded,
        do: [:schema_version, :values],
        else: [:scope, :schema_version, :values]

    changeset =
      settings
      |> cast(attributes, fields)
      |> validate_required([:scope, :schema_version, :values])
      |> validate_length(:scope, min: 1, max: 255)
      |> validate_number(:schema_version, greater_than: 0)
      |> check_constraint(:schema_version, name: :runtime_settings_schema_version_positive)
      |> check_constraint(:version, name: :runtime_settings_version_positive)

    if settings.__meta__.state == :loaded,
      do: optimistic_lock(changeset, :version),
      else: changeset
  end
end
