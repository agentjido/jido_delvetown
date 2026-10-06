defmodule JidoDelvetown.Settings.SetupTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Settings
  alias JidoDelvetown.Settings.{Bootstrap, Setup}

  defmodule TestSession do
    def disconnect do
      send(Application.fetch_env!(:jido_delvetown, :setup_test_owner), :setup_disconnect)
      :ok
    end

    def connect do
      send(Application.fetch_env!(:jido_delvetown, :setup_test_owner), :setup_connect)
      Application.fetch_env!(:jido_delvetown, :setup_connection_result)
    end
  end

  setup do
    old_owner = Application.get_env(:jido_delvetown, :setup_test_owner)
    old_result = Application.get_env(:jido_delvetown, :setup_connection_result)
    Application.put_env(:jido_delvetown, :setup_test_owner, self())

    Application.put_env(
      :jido_delvetown,
      :setup_connection_result,
      {:ok, %{did: "did:plc:agent", handle: "agent.test"}}
    )

    on_exit(fn ->
      restore_env(:setup_test_owner, old_owner)
      restore_env(:setup_connection_result, old_result)
    end)

    %{scope: bootstrap_scope()}
  end

  test "saves encrypted credentials and a safe initial policy", %{scope: scope} do
    assert {:ok, initial} =
             Setup.status(scope: scope, env_reader: fn _name -> nil end)

    assert initial.required?
    refute initial.password_configured?
    refute initial.llm_key.configured?

    assert {:ok, updated} =
             Setup.save(
               %{
                 "identifier" => " agent.test ",
                 "app_password" => " app-password ",
                 "decision_model" => "openai:gpt-5-mini",
                 "autonomy_mode" => "review",
                 "settings_version" => Integer.to_string(initial.settings_version)
               },
               scope: scope
             )

    assert updated.values.account_identifier == "agent.test"
    assert updated.values.account_app_password == "[REDACTED]"
    assert updated.values.decision_model == "openai:gpt-5-mini"
    assert updated.values.autonomy_mode == "review"

    assert {:ok, secret} = Settings.fetch_secret(:account_app_password, scope: scope)
    assert secret.value == "app-password"

    assert {:ok, complete} =
             Setup.status(scope: scope, env_reader: fn "OPENAI_API_KEY" -> "present" end)

    refute complete.required?
    assert complete.password_configured?
    assert complete.llm_key.configured?
    assert complete.llm_key.environment == "OPENAI_API_KEY"
  end

  test "rejects unsafe autonomy and unsupported model choices", %{scope: scope} do
    base = %{
      "identifier" => "agent.test",
      "app_password" => "app-password",
      "decision_model" => "openai:gpt-4o-mini",
      "autonomy_mode" => "observe",
      "settings_version" => "1"
    }

    assert {:error, {:invalid_setup_value, "autonomy_mode"}} =
             Setup.save(%{base | "autonomy_mode" => "autonomous"}, scope: scope)

    assert {:error, {:invalid_setup_value, "decision_model"}} =
             Setup.save(%{base | "decision_model" => "other:model"}, scope: scope)
  end

  test "reconnects the runtime to test the saved DelveTown credentials" do
    assert {:ok, %{did: "did:plc:agent", handle: "agent.test"}} =
             Setup.test_connection(session: TestSession)

    assert_received :setup_disconnect
    assert_received :setup_connect
  end

  defp bootstrap_scope do
    scope = "setup-test-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)
    scope
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_delvetown, key)
  defp restore_env(key, value), do: Application.put_env(:jido_delvetown, key, value)
end
