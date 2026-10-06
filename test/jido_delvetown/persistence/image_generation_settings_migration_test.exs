defmodule JidoDelvetown.ImageGenerationSettingsMigrationTest do
  use ExUnit.Case, async: false

  defmodule MigrationRepo do
    use Ecto.Repo,
      otp_app: :jido_delvetown,
      adapter: Ecto.Adapters.SQLite3
  end

  @migration 20_261_006_000_005

  setup do
    database =
      Path.join(
        System.tmp_dir!(),
        "jido_delvetown_generation_settings_#{System.unique_integer([:positive, :monotonic])}.sqlite3"
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

  test "upgrades an existing settings row with disabled generation defaults" do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    MigrationRepo.query!(
      """
      INSERT INTO runtime_settings
        (scope, schema_version, version, "values", inserted_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      """,
      ["upgrade-test", 2, 7, Jason.encode!(%{"manual_publish_enabled" => false}), now, now]
    )

    Ecto.Migrator.up(
      MigrationRepo,
      @migration,
      JidoDelvetown.Repo.Migrations.AddImageGenerationSettings,
      log: false
    )

    assert [[3, 0, "openai", "gpt-image-1-mini", "1024x1024", 1, "[\"manual\"]", 0, 7]] =
             migrated_row()

    Ecto.Migrator.down(
      MigrationRepo,
      @migration,
      JidoDelvetown.Repo.Migrations.AddImageGenerationSettings,
      log: false
    )

    assert [[2, nil, nil, nil, nil, nil, nil, 0, 7]] = migrated_row()
  end

  defp migrated_row do
    MigrationRepo.query!("""
    SELECT
      schema_version,
      json_extract("values", '$.image_generation_enabled'),
      json_extract("values", '$.image_generation_provider'),
      json_extract("values", '$.image_generation_model'),
      json_extract("values", '$.image_generation_size'),
      json_extract("values", '$.daily_image_generation_limit'),
      json_extract("values", '$.image_generation_allowed_modes'),
      json_extract("values", '$.manual_publish_enabled'),
      version
    FROM runtime_settings
    WHERE scope = 'upgrade-test'
    """).rows
  end
end
