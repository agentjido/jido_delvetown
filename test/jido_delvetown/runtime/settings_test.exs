defmodule JidoDelvetown.SettingsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings
  alias JidoDelvetown.Settings.Bootstrap
  alias JidoDelvetown.Storage.SettingsRevision

  test "reads the current settings with typed keys and a version" do
    scope = bootstrap_scope()

    assert {:ok, current} = Settings.current(scope: scope)
    assert current.scope == scope
    assert current.schema_version == 1
    assert current.version == 1
    assert current.values.autonomy_mode == "observe"
    assert is_integer(current.values.daily_reply_limit)

    assert {:ok, setting} = Settings.fetch("daily_reply_limit", scope: scope)
    assert setting.key == :daily_reply_limit
    assert setting.value == current.values.daily_reply_limit
    assert setting.version == current.version

    assert {:error, {:unknown_setting, :missing}} = Settings.fetch(:missing, scope: scope)
  end

  test "updates settings and revision history in one version" do
    scope = bootstrap_scope()

    assert {:ok, first} = Settings.current(scope: scope)

    assert {:ok, updated} =
             Settings.update(
               %{:daily_reply_limit => 8, "decision_timeout_ms" => 60_000},
               scope: scope,
               expected_version: first.version,
               source: "operator",
               metadata: %{"request_id" => "settings-test"}
             )

    assert updated.version == first.version + 1
    assert updated.values.daily_reply_limit == 8
    assert updated.values.decision_timeout_ms == 60_000

    assert revision = revision(scope, updated.version)
    assert revision.values["daily_reply_limit"] == 8
    assert revision.values["decision_timeout_ms"] == 60_000
    assert revision.source == "operator"
    assert revision.metadata == %{"request_id" => "settings-test"}
  end

  test "does not add a revision for an unchanged value" do
    scope = bootstrap_scope()
    assert {:ok, current} = Settings.current(scope: scope)

    assert {:ok, unchanged} =
             Settings.update(%{daily_reply_limit: current.values.daily_reply_limit},
               scope: scope,
               expected_version: current.version
             )

    assert unchanged == current
    assert revision_count(scope) == 1
  end

  test "rejects invalid values, duplicate aliases, and settings outside the database" do
    scope = bootstrap_scope()

    assert {:error, {:invalid_setting, :dashboard_port, :above_maximum}} =
             Settings.update(%{dashboard_port: 70_000}, scope: scope)

    assert {:error, {:duplicate_setting, :daily_reply_limit}} =
             Settings.update(
               [{:daily_reply_limit, 5}, {"daily_reply_limit", 6}],
               scope: scope
             )

    assert {:error, {:setting_not_persisted, :data_dir}} =
             Settings.update(%{data_dir: "/tmp/other"}, scope: scope)

    assert {:error, {:secure_storage_required, :account_app_password}} =
             Settings.update(%{account_app_password: "plain-text"}, scope: scope)

    assert revision_count(scope) == 1
  end

  test "rejects an invalid combination without changing either row" do
    scope = bootstrap_scope()
    assert {:ok, current} = Settings.current(scope: scope)

    assert {:error,
            {:invalid_settings_combination, :conversation_non_response_limit_exceeds_turn_limit}} =
             Settings.update(
               %{conversation_turn_limit: 2, conversation_non_response_limit: 3},
               scope: scope,
               expected_version: current.version
             )

    assert {:ok, unchanged} = Settings.current(scope: scope)
    assert unchanged == current
    assert revision_count(scope) == 1
  end

  test "rolls back the active row when its revision cannot be written" do
    scope = bootstrap_scope()
    assert {:ok, current} = Settings.current(scope: scope)

    %SettingsRevision{}
    |> SettingsRevision.insert_changeset(%{
      settings_scope: scope,
      version: current.version + 1,
      schema_version: current.schema_version,
      values: revision(scope, current.version).values,
      source: "reserved"
    })
    |> Repo.insert!()

    assert {:error, {:settings_write_failed, changeset}} =
             Settings.update(%{daily_reply_limit: 9},
               scope: scope,
               expected_version: current.version
             )

    refute changeset.valid?
    assert {:ok, unchanged} = Settings.current(scope: scope)
    assert unchanged == current
  end

  test "requires explicit confirmation for protected values" do
    scope = bootstrap_scope()

    assert {:error, {:confirmation_required, :autonomy_mode, "autonomous"}} =
             Settings.update(%{autonomy_mode: "autonomous"}, scope: scope)

    assert {:ok, autonomous} =
             Settings.update(%{autonomy_mode: "autonomous"},
               scope: scope,
               confirmed: [:autonomy_mode]
             )

    assert autonomous.values.autonomy_mode == "autonomous"

    assert {:error, {:confirmation_required, :mark_notifications_seen, true}} =
             Settings.update(%{mark_notifications_seen: true}, scope: scope)

    assert {:ok, confirmed} =
             Settings.update(%{mark_notifications_seen: true},
               scope: scope,
               confirmed: ["mark_notifications_seen"]
             )

    assert confirmed.values.mark_notifications_seen
  end

  test "rejects a stale expected version" do
    scope = bootstrap_scope()
    assert {:ok, first} = Settings.current(scope: scope)

    assert {:ok, second} =
             Settings.update(%{daily_like_limit: 6},
               scope: scope,
               expected_version: first.version
             )

    assert {:error, {:stale_settings, expected, actual}} =
             Settings.update(%{daily_like_limit: 7},
               scope: scope,
               expected_version: first.version
             )

    assert expected == first.version
    assert actual == second.version
    assert revision_count(scope) == 2
  end

  test "allows only one concurrent update for one expected version" do
    scope = bootstrap_scope()
    assert {:ok, current} = Settings.current(scope: scope)
    expected_version = current.version

    results =
      [10, 11]
      |> Task.async_stream(
        fn limit ->
          Settings.update(%{daily_follow_limit: limit},
            scope: scope,
            expected_version: current.version
          )
        end,
        max_concurrency: 2,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _settings}, &1)) == 1

    assert Enum.count(
             results,
             &match?({:error, {:stale_settings, ^expected_version, _actual}}, &1)
           ) == 1

    assert revision_count(scope) == 2
  end

  defp bootstrap_scope do
    scope = "settings-test-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)
    scope
  end

  defp revision(scope, version) do
    Repo.one(
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
