defmodule JidoDelvetown.Settings.Contract do
  @moduledoc """
  Defines every operator setting and the inputs that must stay outside SQLite.

  Database settings use JSON-safe defaults and values. DelveTown credentials use
  encrypted storage. LLM API keys stay in the environment and never enter the
  settings database or revision history.

  Activation values have these meanings:

    * `:immediate` applies to the next request.
    * `:next_cycle` applies when the next participation cycle starts.
    * `:session_reconnect` applies after the DelveTown session reconnects.
    * `:worker_reconcile` applies after Oban schedules are reconciled.
    * `:application_restart` applies after a restart.
    * `:one_time` is a setup input and is not retained.

  """

  @schema_version 2

  @action_values ~w(reply like repost post follow welcome)
  @autonomy_values ~w(observe review autonomous)
  @console_theme_values ~w(system light dark)
  @default_data_dir Path.expand("../../../../tmp/jido_delvetown", __DIR__)

  @standard_safety %{
    classification: :public,
    change_policy: :validated,
    log_policy: :allow
  }
  @private_safety %{
    classification: :private,
    change_policy: :validated,
    log_policy: :redact
  }
  @secret_safety %{
    classification: :secret,
    change_policy: :validated,
    log_policy: :redact
  }
  @autonomy_safety %{
    classification: :public,
    change_policy: {:confirm_value, "autonomous"},
    log_policy: :allow
  }
  @remote_write_safety %{
    classification: :public,
    change_policy: {:confirm_value, true},
    log_policy: :allow
  }

  @definitions [
    %{
      key: :account_identifier,
      section: :connection,
      type: :string,
      default: nil,
      validation: %{allow_nil: true, min_length: 1, max_length: 320},
      storage: :database,
      revision: :record,
      safety: @private_safety,
      activation: :session_reconnect,
      legacy_env: "DELVETOWN_IDENTIFIER"
    },
    %{
      key: :account_app_password,
      section: :connection,
      type: :string,
      default: nil,
      validation: %{allow_nil: true, min_length: 1, max_length: 1_024},
      storage: :encrypted_database,
      revision: :redact,
      safety: @secret_safety,
      activation: :session_reconnect,
      legacy_env: "DELVETOWN_APP_PASSWORD"
    },
    %{
      key: :pds_url,
      section: :connection,
      type: :string,
      default: "https://pds.delve.town",
      validation: %{format: :safe_http_uri, max_length: 2_048},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :session_reconnect,
      legacy_env: "DELVETOWN_PDS_URL"
    },
    %{
      key: :appview_did,
      section: :connection,
      type: :string,
      default: "did:web:api.delve.town",
      validation: %{format: :did, max_length: 512},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :session_reconnect,
      legacy_env: "DELVETOWN_APPVIEW_DID"
    },
    %{
      key: :dashboard_enabled,
      section: :console,
      type: :boolean,
      default: true,
      validation: %{},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :application_restart,
      legacy_env: "DELVETOWN_DASHBOARD_ENABLED"
    },
    %{
      key: :dashboard_port,
      section: :console,
      type: :integer,
      default: 4_040,
      validation: %{min: 1, max: 65_535},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :application_restart,
      legacy_env: "DELVETOWN_DASHBOARD_PORT"
    },
    %{
      key: :console_theme,
      section: :console,
      type: :enum,
      default: "system",
      validation: %{values: @console_theme_values},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :immediate,
      legacy_env: nil
    },
    %{
      key: :decision_model,
      section: :behavior,
      type: :string,
      default: "openai:gpt-4o-mini",
      validation: %{min_length: 1, max_length: 255},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_MODEL"
    },
    %{
      key: :decision_timeout_ms,
      section: :behavior,
      type: :integer,
      default: 45_000,
      validation: %{min: 1_000, max: 180_000},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_DECISION_TIMEOUT_MS"
    },
    %{
      key: :autonomy_mode,
      section: :behavior,
      type: :enum,
      default: "observe",
      validation: %{values: @autonomy_values},
      storage: :database,
      revision: :record,
      safety: @autonomy_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_WRITE_ENABLED"
    },
    %{
      key: :enabled_actions,
      section: :behavior,
      type: {:list, :string},
      default: @action_values,
      validation: %{values: @action_values, unique: true},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: nil
    },
    %{
      key: :manual_publish_enabled,
      section: :behavior,
      type: :boolean,
      default: false,
      validation: %{},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :immediate,
      legacy_env: "DELVETOWN_MANUAL_PUBLISH_ENABLED"
    },
    %{
      key: :dry_run_mark_actioned,
      section: :behavior,
      type: :boolean,
      default: false,
      validation: %{},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_DRY_RUN_MARK_ACTIONED"
    },
    %{
      key: :mark_notifications_seen,
      section: :behavior,
      type: :boolean,
      default: false,
      validation: %{},
      storage: :database,
      revision: :record,
      safety: @remote_write_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_MARK_NOTIFICATIONS_SEEN"
    },
    %{
      key: :notification_limit,
      section: :limits,
      type: :integer,
      default: 20,
      validation: %{min: 1, max: 100},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_NOTIFICATION_LIMIT"
    },
    %{
      key: :daily_reply_limit,
      section: :limits,
      type: :integer,
      default: 3,
      validation: %{min: 0, max: 100},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_DAILY_REPLY_LIMIT"
    },
    %{
      key: :daily_post_limit,
      section: :limits,
      type: :integer,
      default: 1,
      validation: %{min: 0, max: 100},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: nil
    },
    %{
      key: :daily_welcome_limit,
      section: :limits,
      type: :integer,
      default: 2,
      validation: %{min: 0, max: 100},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_DAILY_WELCOME_LIMIT"
    },
    %{
      key: :daily_follow_limit,
      section: :limits,
      type: :integer,
      default: 5,
      validation: %{min: 0, max: 100},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: nil
    },
    %{
      key: :daily_like_limit,
      section: :limits,
      type: :integer,
      default: 5,
      validation: %{min: 0, max: 100},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_DAILY_LIKE_LIMIT"
    },
    %{
      key: :like_actor_cooldown_hours,
      section: :limits,
      type: :integer,
      default: 24,
      validation: %{min: 1, max: 720},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_LIKE_ACTOR_COOLDOWN_HOURS"
    },
    %{
      key: :like_candidate_max_age_hours,
      section: :limits,
      type: :integer,
      default: 48,
      validation: %{min: 1, max: 720},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_LIKE_CANDIDATE_MAX_AGE_HOURS"
    },
    %{
      key: :member_discovery_limit,
      section: :limits,
      type: :integer,
      default: 20,
      validation: %{min: 1, max: 100},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_MEMBER_DISCOVERY_LIMIT"
    },
    %{
      key: :member_max_age_hours,
      section: :limits,
      type: :integer,
      default: 24,
      validation: %{min: 1, max: 720},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_MEMBER_MAX_AGE_HOURS"
    },
    %{
      key: :friend_sync_limit,
      section: :limits,
      type: :integer,
      default: 1_000,
      validation: %{min: 1, max: 10_000},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_FRIEND_SYNC_LIMIT"
    },
    %{
      key: :conversation_turn_limit,
      section: :limits,
      type: :integer,
      default: 4,
      validation: %{min: 1, max: 100},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_CONVERSATION_TURN_LIMIT"
    },
    %{
      key: :conversation_max_age_hours,
      section: :limits,
      type: :integer,
      default: 72,
      validation: %{min: 1, max: 8_760},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_CONVERSATION_MAX_AGE_HOURS"
    },
    %{
      key: :conversation_non_response_limit,
      section: :limits,
      type: :integer,
      default: 2,
      validation: %{min: 1, max: 20},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :next_cycle,
      legacy_env: "DELVETOWN_CONVERSATION_NON_RESPONSE_LIMIT"
    },
    %{
      key: :reactive_review_cron,
      section: :schedules,
      type: :cron,
      default: "*/15 * * * *",
      validation: %{},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :worker_reconcile,
      legacy_env: nil
    },
    %{
      key: :proactive_review_cron,
      section: :schedules,
      type: :cron,
      default: "5,35 * * * *",
      validation: %{},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :worker_reconcile,
      legacy_env: nil
    },
    %{
      key: :member_discovery_cron,
      section: :schedules,
      type: :cron,
      default: "7 * * * *",
      validation: %{},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :worker_reconcile,
      legacy_env: nil
    },
    %{
      key: :friend_sync_cron,
      section: :schedules,
      type: :cron,
      default: "17 * * * *",
      validation: %{},
      storage: :database,
      revision: :record,
      safety: @standard_safety,
      activation: :worker_reconcile,
      legacy_env: nil
    },
    %{
      key: :data_dir,
      section: :bootstrap,
      type: :string,
      default: @default_data_dir,
      validation: %{min_length: 1, max_length: 4_096},
      storage: :bootstrap_environment,
      revision: :exclude,
      safety: @private_safety,
      activation: :application_restart,
      legacy_env: "DELVETOWN_DATA_DIR"
    },
    %{
      key: :database_path,
      section: :bootstrap,
      type: :string,
      default: Path.join(@default_data_dir, "jido_delvetown.sqlite3"),
      validation: %{min_length: 1, max_length: 4_096},
      storage: :bootstrap_environment,
      revision: :exclude,
      safety: @private_safety,
      activation: :application_restart,
      legacy_env: "DELVETOWN_DATABASE_PATH"
    },
    %{
      key: :legacy_import_enabled,
      section: :bootstrap,
      type: :boolean,
      default: true,
      validation: %{},
      storage: :bootstrap_environment,
      revision: :exclude,
      safety: @standard_safety,
      activation: :application_restart,
      legacy_env: "DELVETOWN_LEGACY_IMPORT_ENABLED"
    },
    %{
      key: :invite_code,
      section: :setup,
      type: :string,
      default: nil,
      validation: %{allow_nil: true, min_length: 1, max_length: 1_024},
      storage: :transient,
      revision: :exclude,
      safety: @secret_safety,
      activation: :one_time,
      legacy_env: "DELVETOWN_INVITE_CODE"
    },
    %{
      key: :openai_api_key,
      section: :external_secrets,
      type: :string,
      default: nil,
      validation: %{allow_nil: true, min_length: 1, max_length: 4_096},
      storage: :external_secret,
      revision: :exclude,
      safety: @secret_safety,
      activation: :application_restart,
      legacy_env: "OPENAI_API_KEY"
    }
  ]

  @definitions_by_key Map.new(@definitions, &{&1.key, &1})
  @definitions_by_name Map.new(@definitions, &{Atom.to_string(&1.key), &1})
  @required_fields ~w(key section type default validation storage revision safety activation legacy_env)a

  @type definition :: %{
          required(:key) => atom(),
          required(:section) => atom(),
          required(:type) => atom() | {:list, atom()},
          required(:default) => term(),
          required(:validation) => map(),
          required(:storage) => atom(),
          required(:revision) => atom(),
          required(:safety) => map(),
          required(:activation) => atom(),
          required(:legacy_env) => String.t() | nil
        }

  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  @spec definitions() :: [definition()]
  def definitions, do: @definitions

  @spec database_definitions() :: [definition()]
  def database_definitions do
    Enum.filter(@definitions, &(&1.storage in [:database, :encrypted_database]))
  end

  @spec external_definitions() :: [definition()]
  def external_definitions do
    Enum.reject(@definitions, &(&1.storage in [:database, :encrypted_database]))
  end

  @spec definition(atom() | String.t()) :: {:ok, definition()} | {:error, term()}
  def definition(key) when is_atom(key), do: fetch_definition(@definitions_by_key, key)
  def definition(key) when is_binary(key), do: fetch_definition(@definitions_by_name, key)
  def definition(key), do: {:error, {:unknown_setting, key}}

  @spec defaults() :: %{required(atom()) => term()}
  def defaults do
    Map.new(database_definitions(), &{&1.key, &1.default})
  end

  @spec validate(atom() | String.t(), term()) :: :ok | {:error, term()}
  def validate(key, value) do
    with {:ok, definition} <- definition(key),
         :ok <- validate_value(value, definition) do
      :ok
    end
  end

  @doc false
  @spec required_fields() :: [atom()]
  def required_fields, do: @required_fields

  defp fetch_definition(definitions, key) do
    case Map.fetch(definitions, key) do
      {:ok, definition} -> {:ok, definition}
      :error -> {:error, {:unknown_setting, key}}
    end
  end

  defp validate_value(nil, %{validation: %{allow_nil: true}}), do: :ok

  defp validate_value(nil, definition),
    do: invalid(definition, :required)

  defp validate_value(value, %{type: :boolean} = definition) do
    if is_boolean(value), do: :ok, else: invalid(definition, :expected_boolean)
  end

  defp validate_value(value, %{type: :integer, validation: validation} = definition) do
    cond do
      not is_integer(value) -> invalid(definition, :expected_integer)
      value < Map.get(validation, :min, value) -> invalid(definition, :below_minimum)
      value > Map.get(validation, :max, value) -> invalid(definition, :above_maximum)
      true -> :ok
    end
  end

  defp validate_value(value, %{type: :enum, validation: validation} = definition) do
    if value in validation.values, do: :ok, else: invalid(definition, :not_allowed)
  end

  defp validate_value(value, %{type: {:list, :string}, validation: validation} = definition) do
    cond do
      not is_list(value) ->
        invalid(definition, :expected_list)

      not Enum.all?(value, &is_binary/1) ->
        invalid(definition, :expected_string_items)

      Map.get(validation, :unique, false) and Enum.uniq(value) != value ->
        invalid(definition, :duplicate_items)

      Enum.any?(value, &(&1 not in Map.get(validation, :values, value))) ->
        invalid(definition, :item_not_allowed)

      true ->
        :ok
    end
  end

  defp validate_value(value, %{type: :cron} = definition) do
    case Oban.Cron.Expression.parse(value) do
      {:ok, _expression} -> :ok
      _other -> invalid(definition, :invalid_cron)
    end
  rescue
    FunctionClauseError -> invalid(definition, :invalid_cron)
  end

  defp validate_value(value, %{type: :string, validation: validation} = definition) do
    cond do
      not is_binary(value) ->
        invalid(definition, :expected_string)

      String.length(value) < Map.get(validation, :min_length, 0) ->
        invalid(definition, :too_short)

      String.length(value) > Map.get(validation, :max_length, String.length(value)) ->
        invalid(definition, :too_long)

      not valid_format?(value, Map.get(validation, :format)) ->
        invalid(definition, :invalid_format)

      true ->
        :ok
    end
  end

  defp valid_format?(_value, nil), do: true

  defp valid_format?(value, :did),
    do: Regex.match?(~r/\Adid:[a-z0-9]+:[^\s]+\z/, value)

  defp valid_format?(value, :safe_http_uri) do
    case URI.parse(value) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        true

      %URI{scheme: "http", host: host}
      when host in ["localhost", "127.0.0.1", "::1"] ->
        true

      _other ->
        false
    end
  end

  defp invalid(definition, reason),
    do: {:error, {:invalid_setting, definition.key, reason}}
end
