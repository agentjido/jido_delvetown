defmodule JidoDelvetown.Storage.SettingsRevision do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "runtime_settings_revisions" do
    field(:settings_scope, :string)
    field(:version, :integer)
    field(:schema_version, :integer)
    field(:values, :map, default: %{})
    field(:source, :string)
    field(:metadata, :map, default: %{})
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def insert_changeset(revision, attributes) do
    revision
    |> cast(attributes, [
      :settings_scope,
      :version,
      :schema_version,
      :values,
      :source,
      :metadata
    ])
    |> validate_required([:settings_scope, :version, :schema_version, :values, :source])
    |> validate_length(:settings_scope, min: 1, max: 255)
    |> validate_length(:source, min: 1, max: 255)
    |> validate_number(:version, greater_than: 0)
    |> validate_number(:schema_version, greater_than: 0)
    |> check_constraint(:version, name: :runtime_settings_revisions_version_positive)
    |> check_constraint(:schema_version,
      name: :runtime_settings_revisions_schema_version_positive
    )
    |> foreign_key_constraint(:settings_scope)
    |> unique_constraint([:settings_scope, :version], error_key: :version)
  end
end
