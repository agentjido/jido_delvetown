defmodule JidoDelvetown.Settings.ContractTest do
  use ExUnit.Case, async: true

  alias JidoDelvetown.Settings.Contract

  @current_delvetown_environment ~w(
    DELVETOWN_APPVIEW_DID
    DELVETOWN_APP_PASSWORD
    DELVETOWN_CONVERSATION_MAX_AGE_HOURS
    DELVETOWN_CONVERSATION_NON_RESPONSE_LIMIT
    DELVETOWN_CONVERSATION_TURN_LIMIT
    DELVETOWN_DAILY_LIKE_LIMIT
    DELVETOWN_DAILY_REPLY_LIMIT
    DELVETOWN_DAILY_WELCOME_LIMIT
    DELVETOWN_DASHBOARD_ENABLED
    DELVETOWN_DASHBOARD_PORT
    DELVETOWN_DATABASE_PATH
    DELVETOWN_DATA_DIR
    DELVETOWN_DECISION_TIMEOUT_MS
    DELVETOWN_DRY_RUN_MARK_ACTIONED
    DELVETOWN_FRIEND_SYNC_LIMIT
    DELVETOWN_IDENTIFIER
    DELVETOWN_INVITE_CODE
    DELVETOWN_LEGACY_IMPORT_ENABLED
    DELVETOWN_LIKE_ACTOR_COOLDOWN_HOURS
    DELVETOWN_LIKE_CANDIDATE_MAX_AGE_HOURS
    DELVETOWN_MANUAL_PUBLISH_ENABLED
    DELVETOWN_MARK_NOTIFICATIONS_SEEN
    DELVETOWN_MEMBER_DISCOVERY_LIMIT
    DELVETOWN_MEMBER_MAX_AGE_HOURS
    DELVETOWN_MODEL
    DELVETOWN_NOTIFICATION_LIMIT
    DELVETOWN_PDS_URL
    DELVETOWN_WRITE_ENABLED
  )

  test "defines complete and unique setting records" do
    definitions = Contract.definitions()
    keys = Enum.map(definitions, & &1.key)

    assert length(keys) == length(Enum.uniq(keys))

    for definition <- definitions do
      assert Map.keys(definition) |> Enum.sort() == Contract.required_fields() |> Enum.sort()
      assert :ok = Contract.validate(definition.key, definition.default)
    end
  end

  test "inventories every current DelveTown environment setting" do
    inventoried =
      Contract.definitions()
      |> Enum.map(& &1.legacy_env)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&String.starts_with?(&1, "DELVETOWN_"))
      |> Enum.sort()

    assert inventoried == Enum.sort(@current_delvetown_environment)
  end

  test "safe database defaults start in observe mode without remote writes" do
    defaults = Contract.defaults()

    assert defaults.console_theme == "system"
    assert defaults.autonomy_mode == "observe"
    refute defaults.manual_publish_enabled
    refute defaults.mark_notifications_seen
    refute defaults.dry_run_mark_actioned

    assert {:ok, autonomy} = Contract.definition(:autonomy_mode)
    assert autonomy.safety.change_policy == {:confirm_value, "autonomous"}

    assert {:ok, notification_updates} = Contract.definition(:mark_notifications_seen)
    assert notification_updates.safety.change_policy == {:confirm_value, true}
  end

  test "keeps credentials encrypted and LLM API keys external" do
    assert {:ok, password} = Contract.definition(:account_app_password)
    assert password.storage == :encrypted_database
    assert password.revision == :redact
    assert password.safety.log_policy == :redact

    assert {:ok, api_key} = Contract.definition(:openai_api_key)
    assert api_key.storage == :external_secret
    assert api_key.revision == :exclude
    refute Map.has_key?(Contract.defaults(), :openai_api_key)
  end

  test "records activation timing for live, session, schedule, and startup changes" do
    assert activation(:manual_publish_enabled) == :immediate
    assert activation(:daily_reply_limit) == :next_cycle
    assert activation(:pds_url) == :session_reconnect
    assert activation(:reactive_review_cron) == :worker_reconcile
    assert activation(:dashboard_port) == :application_restart
    assert activation(:invite_code) == :one_time
  end

  test "validates bounded values, action lists, endpoints, DIDs, and cron expressions" do
    assert :ok = Contract.validate(:dashboard_port, 4_041)

    assert {:error, {:invalid_setting, :dashboard_port, :below_minimum}} =
             Contract.validate(:dashboard_port, 0)

    assert :ok = Contract.validate(:enabled_actions, ["reply", "like"])

    assert {:error, {:invalid_setting, :enabled_actions, :item_not_allowed}} =
             Contract.validate(:enabled_actions, ["delete"])

    assert :ok = Contract.validate(:pds_url, "https://pds.delve.town")
    assert :ok = Contract.validate(:pds_url, "http://localhost:2583")

    assert {:error, {:invalid_setting, :pds_url, :invalid_format}} =
             Contract.validate(:pds_url, "http://remote.example")

    assert :ok = Contract.validate(:appview_did, "did:web:api.delve.town")
    assert :ok = Contract.validate(:friend_sync_cron, "17 * * * *")
    assert :ok = Contract.validate(:console_theme, "light")

    assert {:error, {:invalid_setting, :console_theme, :not_allowed}} =
             Contract.validate(:console_theme, "sepia")

    assert {:error, {:invalid_setting, :friend_sync_cron, :invalid_cron}} =
             Contract.validate(:friend_sync_cron, "not a cron")
  end

  test "accepts stable string keys without creating atoms" do
    assert {:ok, %{key: :daily_like_limit}} = Contract.definition("daily_like_limit")
    assert :ok = Contract.validate("daily_like_limit", 5)

    assert {:error, {:unknown_setting, "new_untrusted_key"}} =
             Contract.definition("new_untrusted_key")
  end

  defp activation(key) do
    {:ok, definition} = Contract.definition(key)
    definition.activation
  end
end
