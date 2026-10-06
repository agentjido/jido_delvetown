defmodule JidoDelvetown.Settings.LegacyEnvImporterTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings
  alias JidoDelvetown.Settings.{Bootstrap, Contract, LegacyEnvImporter}
  alias JidoDelvetown.Storage.{AuditEvent, LegacyImport, SettingsRevision}

  test "previews typed values and hides private and secret values" do
    env = %{
      "DELVETOWN_IDENTIFIER" => "agent.test",
      "DELVETOWN_APP_PASSWORD" => "secret-password",
      "DELVETOWN_DASHBOARD_ENABLED" => "off",
      "DELVETOWN_DASHBOARD_PORT" => "4041",
      "DELVETOWN_WRITE_ENABLED" => "yes",
      "OPENAI_API_KEY" => "must-not-enter-sqlite",
      "DELVETOWN_DATA_DIR" => "/tmp/not-a-runtime-setting",
      "DELVETOWN_INVITE_CODE" => "not-imported"
    }

    assert {:ok, preview} = LegacyEnvImporter.preview(env: env)
    assert preview.status == :ready
    assert preview.count == 5
    assert preview.ignored_external_secrets == ["OPENAI_API_KEY"]

    assert value(preview, :account_identifier) == "[REDACTED]"
    assert value(preview, :account_app_password) == "[REDACTED]"
    assert value(preview, :dashboard_enabled) == false
    assert value(preview, :dashboard_port) == 4_041
    assert value(preview, :autonomy_mode) == "autonomous"

    refute Enum.any?(preview.settings, &(&1.environment == "DELVETOWN_DATA_DIR"))
    refute Enum.any?(preview.settings, &(&1.environment == "DELVETOWN_INVITE_CODE"))
    refute inspect(preview) =~ "secret-password"
    refute inspect(preview) =~ "must-not-enter-sqlite"
  end

  test "imports fresh settings with confirmations, encryption, and a safe audit" do
    context = bootstrap_context()

    env = %{
      "DELVETOWN_IDENTIFIER" => "agent.test",
      "DELVETOWN_APP_PASSWORD" => "secret-password",
      "DELVETOWN_WRITE_ENABLED" => "true",
      "DELVETOWN_MARK_NOTIFICATIONS_SEEN" => "1",
      "DELVETOWN_DAILY_REPLY_LIMIT" => "9",
      "OPENAI_API_KEY" => "must-not-enter-sqlite"
    }

    assert {:ok, {:imported, details}} =
             LegacyEnvImporter.run(context.opts ++ [env: env])

    assert details["status"] == "imported"
    assert details["count"] == 5
    assert details["settings_version"] == 2
    assert details["ignored_external_secrets"] == ["OPENAI_API_KEY"]

    assert {:ok, current} = Settings.current(scope: context.scope)
    assert current.values.account_identifier == "agent.test"
    assert current.values.account_app_password == "[REDACTED]"
    assert current.values.autonomy_mode == "autonomous"
    assert current.values.mark_notifications_seen
    assert current.values.daily_reply_limit == 9

    assert {:ok, secret} = Settings.fetch_secret(:account_app_password, scope: context.scope)
    assert secret.value == "secret-password"

    revision = revision(context.scope, 2)
    assert revision.source == "legacy_environment"
    assert revision.values["account_app_password"] == "[REDACTED]"

    legacy_import = Repo.get!(LegacyImport, context.import_name)
    audit = Repo.get_by!(AuditEvent, source_key: context.audit_source)
    persisted = inspect([legacy_import.details, audit.data, revision.metadata, revision.values])

    refute persisted =~ "secret-password"
    refute persisted =~ "must-not-enter-sqlite"
  end

  test "a completed marker prevents later environment changes" do
    context = bootstrap_context()

    assert {:ok, {:imported, first}} =
             LegacyEnvImporter.run(context.opts ++ [env: %{"DELVETOWN_DAILY_REPLY_LIMIT" => "8"}])

    assert {:ok, {:reused, second}} =
             LegacyEnvImporter.run(
               context.opts ++ [env: %{"DELVETOWN_DAILY_REPLY_LIMIT" => "10"}]
             )

    assert second == first
    assert {:ok, current} = Settings.current(scope: context.scope)
    assert current.values.daily_reply_limit == 8
    assert current.version == 2
    assert revision_count(context.scope) == 2
  end

  test "does not overwrite settings that an operator already changed" do
    context = bootstrap_context()

    assert {:ok, changed} =
             Settings.update(%{daily_reply_limit: 7}, scope: context.scope, source: "operator")

    assert {:ok, {:skipped, details}} =
             LegacyEnvImporter.run(
               context.opts ++ [env: %{"DELVETOWN_DAILY_REPLY_LIMIT" => "10"}]
             )

    assert details["status"] == "skipped_existing_settings"
    assert details["settings_version"] == changed.version
    assert {:ok, current} = Settings.current(scope: context.scope)
    assert current.values.daily_reply_limit == 7
    assert revision_count(context.scope) == 2
  end

  test "invalid values make no settings or marker changes" do
    context = bootstrap_context()

    assert {:error,
            {:invalid_legacy_environment, "DELVETOWN_DASHBOARD_PORT", :dashboard_port,
             :expected_integer}} =
             LegacyEnvImporter.run(context.opts ++ [env: %{"DELVETOWN_DASHBOARD_PORT" => "many"}])

    assert {:ok, current} = Settings.current(scope: context.scope)
    assert current.version == 1
    assert current.values == Contract.defaults()
    refute Repo.get(LegacyImport, context.import_name)
    refute Repo.get_by(AuditEvent, source_key: context.audit_source)
  end

  test "records an empty environment check one time" do
    context = bootstrap_context()

    assert {:ok, {:imported, details}} = LegacyEnvImporter.run(context.opts ++ [env: %{}])
    assert details["status"] == "no_values"
    assert details["count"] == 0

    assert {:ok, {:reused, ^details}} =
             LegacyEnvImporter.run(
               context.opts ++ [env: %{"DELVETOWN_DAILY_REPLY_LIMIT" => "10"}]
             )

    assert {:ok, current} = Settings.current(scope: context.scope)
    assert current.version == 1
  end

  test "recovers a completed settings update when its marker is missing" do
    context = bootstrap_context()
    checksum = String.duplicate("a", 64)

    assert {:ok, updated} =
             Settings.update(%{daily_reply_limit: 8},
               scope: context.scope,
               source: "legacy_environment",
               metadata: %{
                 "legacy_import_name" => context.import_name,
                 "checksum" => checksum,
                 "setting_keys" => ["daily_reply_limit"],
                 "environment_names" => ["DELVETOWN_DAILY_REPLY_LIMIT"]
               }
             )

    assert {:ok, {:imported, details}} =
             LegacyEnvImporter.run(
               context.opts ++ [env: %{"DELVETOWN_DAILY_REPLY_LIMIT" => "bad"}]
             )

    assert details["recovered"]
    assert details["settings_version"] == updated.version
    assert Repo.get!(LegacyImport, context.import_name).checksum == checksum
    assert {:ok, current} = Settings.current(scope: context.scope)
    assert current.values.daily_reply_limit == 8
  end

  defp bootstrap_context do
    id = System.unique_integer([:positive, :monotonic])
    scope = "legacy-env-test-#{id}"
    import_name = "legacy-environment-test-#{id}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)

    %{
      scope: scope,
      import_name: import_name,
      audit_source: "legacy:settings:#{import_name}",
      opts: [scope: scope, import_name: import_name]
    }
  end

  defp value(preview, key) do
    preview.settings
    |> Enum.find(&(&1.key == key))
    |> Map.fetch!(:value)
  end

  defp revision(scope, version) do
    Repo.one!(
      from(revision in SettingsRevision,
        where: revision.settings_scope == ^scope and revision.version == ^version
      )
    )
  end

  defp revision_count(scope) do
    Repo.aggregate(
      from(revision in SettingsRevision, where: revision.settings_scope == ^scope),
      :count
    )
  end
end
