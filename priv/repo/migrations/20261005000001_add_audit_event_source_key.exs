defmodule JidoDelvetown.Repo.Migrations.AddAuditEventSourceKey do
  use Ecto.Migration

  def change do
    alter table(:audit_events) do
      add(:source_key, :string)
    end

    create(unique_index(:audit_events, [:source_key]))
  end
end
