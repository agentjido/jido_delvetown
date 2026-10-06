defmodule JidoDelvetown.ConsoleThemeMigrationTest do
  use ExUnit.Case, async: false

  defmodule MigrationRepo do
    use Ecto.Repo,
      otp_app: :jido_delvetown,
      adapter: Ecto.Adapters.SQLite3
  end

  @theme_migration 20_261_006_000_002

  setup do
    database =
      Path.join(
        System.tmp_dir!(),
        "jido_delvetown_theme_migration_#{System.unique_integer([:positive, :monotonic])}.sqlite3"
      )

    start_supervised!({MigrationRepo, database: database, pool_size: 1})

    MigrationRepo.query!("""
    CREATE TABLE runtime_settings (
      scope TEXT PRIMARY KEY,
      schema_version INTEGER NOT NULL,
      version INTEGER NOT NULL,
      "values" TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    on_exit(fn ->
      for suffix <- ["", "-shm", "-wal"], do: File.rm(database <> suffix)
    end)

    :ok
  end

  test "upgrades an existing settings row and can remove the theme" do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    MigrationRepo.query!(
      """
      INSERT INTO runtime_settings
        (scope, schema_version, version, "values", inserted_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      """,
      ["upgrade-test", 1, 7, Jason.encode!(%{"autonomy_mode" => "observe"}), now, now]
    )

    Ecto.Migrator.up(
      MigrationRepo,
      @theme_migration,
      JidoDelvetown.Repo.Migrations.AddConsoleTheme,
      log: false
    )

    assert [[2, "system", 7]] = migrated_row()

    Ecto.Migrator.down(
      MigrationRepo,
      @theme_migration,
      JidoDelvetown.Repo.Migrations.AddConsoleTheme,
      log: false
    )

    assert [[1, nil, 7]] = migrated_row()
  end

  defp migrated_row do
    MigrationRepo.query!("""
    SELECT schema_version, json_extract("values", '$.console_theme'), version
    FROM runtime_settings
    WHERE scope = 'upgrade-test'
    """).rows
  end
end
