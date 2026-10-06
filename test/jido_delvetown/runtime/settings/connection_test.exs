defmodule JidoDelvetown.Settings.ConnectionTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Settings
  alias JidoDelvetown.Settings.{Bootstrap, Connection}

  test "reads connection, identity, and dashboard values from SQLite settings" do
    scope = bootstrap_scope()

    assert {:error, {:connection_setting_missing, :account_identifier}} =
             Connection.credentials(scope: scope)

    assert {:ok, "https://pds.delve.town"} = Connection.pds_url(scope: scope)
    assert {:ok, "did:web:api.delve.town"} = Connection.appview_did(scope: scope)

    assert {:ok, "did:web:api.delve.town#bsky_appview"} =
             Connection.proxy_header(scope: scope)

    assert {:ok, %{enabled?: true, port: 4_040}} = Connection.dashboard(scope: scope)
    refute Connection.credentials_configured?(scope: scope)

    assert {:ok, _updated} =
             Settings.update(
               %{
                 account_identifier: "agent.test",
                 account_app_password: "app-password",
                 pds_url: "https://pds.test",
                 appview_did: "did:web:appview.test",
                 dashboard_enabled: false,
                 dashboard_port: 4_141
               },
               scope: scope
             )

    assert {:ok, %{identifier: "agent.test", password: "app-password"}} =
             Connection.credentials(scope: scope)

    assert Connection.credentials_configured?(scope: scope)
    assert {:ok, "https://pds.test"} = Connection.pds_url(scope: scope)
    assert {:ok, "did:web:appview.test#bsky_appview"} = Connection.proxy_header(scope: scope)
    assert {:ok, %{enabled?: false, port: 4_141}} = Connection.dashboard(scope: scope)
  end

  defp bootstrap_scope do
    scope = "connection-test-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)
    scope
  end
end
