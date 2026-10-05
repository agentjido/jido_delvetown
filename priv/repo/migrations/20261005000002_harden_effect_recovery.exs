defmodule JidoDelvetown.Repo.Migrations.HardenEffectRecovery do
  use Ecto.Migration

  def up do
    drop_if_exists(index(:effects, [:rkey]))
    create(index(:effects, [:rkey], name: :effects_lookup_rkey_index))

    execute("UPDATE effects SET status = 'completed' WHERE status = 'complete'")
  end

  def down do
    execute("UPDATE effects SET status = 'complete' WHERE status = 'completed'")

    drop_if_exists(index(:effects, [:rkey], name: :effects_lookup_rkey_index))
    create(unique_index(:effects, [:rkey]))
  end
end
