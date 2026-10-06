defmodule JidoDelvetown.Settings.ConsoleTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings.{Bootstrap, Console}
  alias JidoDelvetown.Storage.SettingsRevision

  test "stores one validated console theme in SQLite" do
    scope = unique_scope()
    assert {:ok, _bootstrap} = Bootstrap.run(scope: scope)

    assert Console.themes() == ~w(system light dark)
    assert {:ok, "system"} = Console.theme(scope: scope)

    assert {:ok, updated} = Console.select_theme("dark", scope: scope)
    assert updated.values.console_theme == "dark"
    assert {:ok, "dark"} = Console.theme(scope: scope)

    revision = Repo.get_by!(SettingsRevision, settings_scope: scope, version: updated.version)
    assert revision.values["console_theme"] == "dark"
    assert revision.source == "operator_console"
  end

  test "rejects a theme outside the console contract" do
    scope = unique_scope()
    assert {:ok, _bootstrap} = Bootstrap.run(scope: scope)

    assert {:error, {:invalid_setting, :console_theme, :not_allowed}} =
             Console.select_theme("high-contrast", scope: scope)

    assert {:ok, "system"} = Console.theme(scope: scope)
  end

  defp unique_scope,
    do: "console-test-#{System.unique_integer([:positive, :monotonic])}"
end
