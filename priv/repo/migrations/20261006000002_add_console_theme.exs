defmodule JidoDelvetown.Repo.Migrations.AddConsoleTheme do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE runtime_settings
    SET schema_version = 2,
        "values" = json_set("values", '$.console_theme', 'system')
    WHERE schema_version = 1
    """)
  end

  def down do
    execute("""
    UPDATE runtime_settings
    SET schema_version = 1,
        "values" = json_remove("values", '$.console_theme')
    WHERE schema_version = 2
    """)
  end
end
