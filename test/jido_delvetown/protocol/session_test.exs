defmodule JidoDelvetown.SessionTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Session
  alias JidoDelvetown.Settings
  alias JidoDelvetown.Settings.{Bootstrap, Connection}

  defmodule Transport do
    def login(identifier, password, opts) do
      send(Application.fetch_env!(:jido_delvetown, :session_test_owner), {
        :login,
        identifier,
        password,
        opts
      })

      {:ok,
       %ProtoRune.Atproto.Session{
         access_jwt: "access-token",
         refresh_jwt: "refresh-token",
         handle: identifier,
         did: "did:plc:agent",
         service_url: Keyword.fetch!(opts, :service) <> "/xrpc"
       }}
    end
  end

  setup do
    previous_owner = Application.get_env(:jido_delvetown, :session_test_owner)
    Application.put_env(:jido_delvetown, :session_test_owner, self())

    on_exit(fn -> restore_env(:session_test_owner, previous_owner) end)
  end

  test "connects with the credentials and PDS URL stored in SQLite" do
    scope = bootstrap_scope()

    assert {:ok, _updated} =
             Settings.update(
               %{
                 account_identifier: "agent.test",
                 account_app_password: "stored-password",
                 pds_url: "https://pds.test"
               },
               scope: scope
             )

    supervisor =
      start_supervised!(
        {DynamicSupervisor, strategy: :one_for_one, name: JidoDelvetown.Test.SessionSupervisor}
      )

    session =
      start_supervised!(
        {Session,
         name: JidoDelvetown.Test.SettingsSession,
         supervisor: supervisor,
         transport: Transport,
         credentials: fn -> Connection.credentials(scope: scope) end,
         service: fn -> Connection.pds_url(scope: scope) end}
      )

    assert {:ok, %{did: "did:plc:agent", handle: "agent.test"}} = Session.connect(session)

    assert_received {:login, "agent.test", "stored-password", [service: "https://pds.test"]}
  end

  defp bootstrap_scope do
    scope = "session-test-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)
    scope
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_delvetown, key)
  defp restore_env(key, value), do: Application.put_env(:jido_delvetown, key, value)
end
