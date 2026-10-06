defmodule JidoDelvetown.Repo.Migrations.AddImageGenerationSettings do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE runtime_settings
    SET schema_version = 3,
        "values" = json_set(
          "values",
          '$.image_generation_enabled', json('false'),
          '$.image_generation_provider', 'openai',
          '$.image_generation_model', 'gpt-image-1-mini',
          '$.image_generation_size', '1024x1024',
          '$.image_generation_quality', 'medium',
          '$.image_generation_output_format', 'png',
          '$.image_generation_timeout_ms', 120000,
          '$.daily_image_generation_limit', 1,
          '$.image_generation_allowed_modes', json('["manual"]')
        )
    WHERE schema_version = 2
    """)
  end

  def down do
    execute("""
    UPDATE runtime_settings
    SET schema_version = 2,
        "values" = json_remove(
          "values",
          '$.image_generation_enabled',
          '$.image_generation_provider',
          '$.image_generation_model',
          '$.image_generation_size',
          '$.image_generation_quality',
          '$.image_generation_output_format',
          '$.image_generation_timeout_ms',
          '$.daily_image_generation_limit',
          '$.image_generation_allowed_modes'
        )
    WHERE schema_version = 3
    """)
  end
end
