defmodule JidoDelvetownWeb.DashboardSettingsTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Settings
  alias JidoDelvetown.Settings.{Bootstrap, Contract}
  alias JidoDelvetownWeb.DashboardSettings

  test "builds the settings form with activation details and safe history" do
    scope = bootstrap_scope()

    assert {:ok, page} = DashboardSettings.load(scope: scope)
    assert page.available?
    assert page.version == 1

    assert Enum.map(page.sections, & &1.key) ==
             ~w(connection behavior limits schedules safety console)

    fields = Enum.flat_map(page.sections, & &1.fields)
    assert Enum.find(fields, &(&1.key == :account_app_password)).input == :password
    assert Enum.find(fields, &(&1.key == :reactive_review_cron)).activation == :worker_reconcile
    assert Enum.find(fields, &(&1.key == :dashboard_port)).activation == :application_restart
    assert [%{version: 1, current?: true, changed: ["Initial settings"]}] = page.history
  end

  test "saves typed values and reports when they become active" do
    scope = bootstrap_scope()
    params = form_params(scope)

    params =
      params
      |> Map.put("daily_reply_limit", "8")
      |> Map.put("console_theme", "dark")
      |> Map.put("reactive_review_cron", "*/20 * * * *")
      |> Map.put("enabled_actions", ["reply", "like"])

    assert {:ok, result} = DashboardSettings.save(params, scope: scope)
    assert result.settings.values.daily_reply_limit == 8
    assert result.settings.values.console_theme == "dark"
    assert result.settings.values.reactive_review_cron == "*/20 * * * *"
    assert result.settings.values.enabled_actions == ["reply", "like"]
    assert "Daily reply limit" in result.changed
    assert Enum.any?(result.activations, &(&1.key == :immediate))
    assert Enum.any?(result.activations, &(&1.key == :next_cycle))
    assert Enum.any?(result.activations, &(&1.key == :worker_reconcile))

    assert {:error, {:invalid_form_value, :daily_reply_limit, :not_an_integer}} =
             params
             |> Map.put("version", Integer.to_string(result.settings.version))
             |> Map.put("daily_reply_limit", "many")
             |> DashboardSettings.save(scope: scope)
  end

  test "requires confirmation for protected settings" do
    scope = bootstrap_scope()
    params = form_params(scope) |> Map.put("autonomy_mode", "autonomous")

    assert {:error, {:confirmation_required, :autonomy_mode, "autonomous"}} =
             DashboardSettings.save(params, scope: scope)

    assert {:ok, result} =
             params
             |> Map.put("confirm_autonomous", "true")
             |> DashboardSettings.save(scope: scope)

    assert result.settings.values.autonomy_mode == "autonomous"
  end

  test "rolls back from history with optimistic locking" do
    scope = bootstrap_scope()
    initial = form_params(scope)

    assert {:ok, changed} =
             initial
             |> Map.put("daily_post_limit", "7")
             |> DashboardSettings.save(scope: scope)

    assert {:ok, result} =
             DashboardSettings.rollback(
               "1",
               %{"version" => Integer.to_string(changed.settings.version)},
               scope: scope
             )

    assert result.target_version == 1
    assert result.settings.values.daily_post_limit == Contract.defaults().daily_post_limit
    assert result.activations == [%{key: :next_cycle, label: "Next cycle"}]
  end

  defp bootstrap_scope do
    scope = "dashboard-settings-test-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)
    scope
  end

  defp form_params(scope) do
    assert {:ok, current} = Settings.current(scope: scope)

    params =
      Contract.database_definitions()
      |> Enum.map(fn definition ->
        value = Map.fetch!(current.values, definition.key)

        form_value =
          cond do
            definition.storage == :encrypted_database -> ""
            is_boolean(value) or is_integer(value) -> to_string(value)
            true -> value
          end

        {Atom.to_string(definition.key), form_value}
      end)
      |> Map.new()

    Map.put(params, "version", Integer.to_string(current.version))
  end
end
