defmodule JidoDelvetownWeb.DashboardSettings do
  @moduledoc false

  alias JidoDelvetown.Settings
  alias JidoDelvetown.Settings.Contract

  @history_limit 8
  @section_keys [
    connection: [:account_identifier, :account_app_password, :pds_url, :appview_did],
    behavior: [:decision_model, :decision_timeout_ms, :enabled_actions],
    limits: [
      :notification_limit,
      :daily_reply_limit,
      :daily_post_limit,
      :daily_welcome_limit,
      :daily_follow_limit,
      :daily_like_limit,
      :like_actor_cooldown_hours,
      :like_candidate_max_age_hours,
      :member_discovery_limit,
      :member_max_age_hours,
      :friend_sync_limit,
      :conversation_turn_limit,
      :conversation_max_age_hours,
      :conversation_non_response_limit
    ],
    schedules: [
      :reactive_review_cron,
      :proactive_review_cron,
      :member_discovery_cron,
      :friend_sync_cron
    ],
    safety: [
      :autonomy_mode,
      :manual_publish_enabled,
      :dry_run_mark_actioned,
      :mark_notifications_seen
    ],
    console: [:console_theme, :dashboard_enabled, :dashboard_port]
  ]
  @editable_keys @section_keys |> Keyword.values() |> List.flatten()

  @section_copy %{
    connection: {"Connection", "Change the DelveTown identity and protocol endpoints."},
    behavior: {"Behavior", "Set the decision model and the actions that the agent can propose."},
    limits: {"Limits", "Set daily budgets, scan sizes, cooldowns, and conversation bounds."},
    schedules: {"Schedules", "Set the Oban cron expressions for recurring work."},
    safety:
      {"Safety", "Control autonomy, manual publish access, and remote notification writes."},
    console: {"Console", "Set the theme and the local dashboard startup values."}
  }

  @labels %{
    account_identifier: "Account identifier",
    account_app_password: "App password",
    pds_url: "PDS URL",
    appview_did: "AppView DID",
    decision_model: "Decision model",
    decision_timeout_ms: "Decision timeout (ms)",
    enabled_actions: "Enabled actions",
    notification_limit: "Notifications per scan",
    daily_reply_limit: "Daily reply limit",
    daily_post_limit: "Daily post limit",
    daily_welcome_limit: "Daily welcome limit",
    daily_follow_limit: "Daily follow limit",
    daily_like_limit: "Daily like limit",
    like_actor_cooldown_hours: "Like actor cooldown (hours)",
    like_candidate_max_age_hours: "Like candidate maximum age (hours)",
    member_discovery_limit: "Members per discovery scan",
    member_max_age_hours: "New member maximum age (hours)",
    friend_sync_limit: "Friends per sync",
    conversation_turn_limit: "Conversation turn limit",
    conversation_max_age_hours: "Conversation maximum age (hours)",
    conversation_non_response_limit: "Non-response limit",
    reactive_review_cron: "Reactive review cron",
    proactive_review_cron: "Proactive review cron",
    member_discovery_cron: "Member discovery cron",
    friend_sync_cron: "Friend sync cron",
    autonomy_mode: "Autonomy mode",
    manual_publish_enabled: "Allow manual publish",
    dry_run_mark_actioned: "Mark dry-run proposals as actioned",
    mark_notifications_seen: "Mark notifications as seen",
    console_theme: "Console theme",
    dashboard_enabled: "Start the dashboard",
    dashboard_port: "Dashboard port"
  }

  @activation_labels %{
    immediate: "Immediate",
    next_cycle: "Next cycle",
    session_reconnect: "After reconnect",
    worker_reconcile: "After worker sync",
    application_restart: "After restart"
  }

  @spec load(keyword()) :: {:ok, map()} | {:error, term()}
  def load(opts \\ []) do
    settings = Keyword.get(opts, :settings, Settings)
    settings_opts = Keyword.take(opts, [:repo, :scope])

    with {:ok, current} <- settings.current(settings_opts),
         {:ok, revisions} <-
           settings.revisions(Keyword.put(settings_opts, :limit, @history_limit + 1)) do
      {:ok,
       %{
         available?: true,
         version: current.version,
         schema_version: current.schema_version,
         sections: sections(current.values),
         history: history(revisions, current.version),
         activation_guide: activation_guide()
       }}
    end
  end

  @spec save(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def save(params, opts \\ [])

  def save(params, opts) when is_map(params) do
    settings = Keyword.get(opts, :settings, Settings)
    settings_opts = Keyword.take(opts, [:repo, :scope])

    with {:ok, current} <- settings.current(settings_opts),
         {:ok, expected_version} <- positive_integer(Map.get(params, "version")),
         {:ok, parsed_changes} <- parse_changes(params),
         changes <- changed_values(parsed_changes, current.values),
         {:ok, updated} <-
           settings.update(
             changes,
             settings_opts ++
               [
                 expected_version: expected_version,
                 confirmed: confirmed_keys(params),
                 source: "operator_console",
                 metadata: %{"workflow" => "settings_editor"}
               ]
           ) do
      {:ok, result(current, updated)}
    end
  end

  def save(_params, _opts), do: {:error, :invalid_settings_form}

  @spec rollback(String.t() | pos_integer(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def rollback(version, params, opts \\ [])

  def rollback(version, params, opts) when is_map(params) do
    settings = Keyword.get(opts, :settings, Settings)
    settings_opts = Keyword.take(opts, [:repo, :scope])

    with {:ok, target_version} <- positive_integer(version),
         {:ok, expected_version} <- positive_integer(Map.get(params, "version")),
         {:ok, current} <- settings.current(settings_opts),
         {:ok, updated} <-
           settings.rollback(
             target_version,
             settings_opts ++
               [
                 expected_version: expected_version,
                 confirmed: confirmed_keys(params),
                 source: "operator_console_rollback",
                 metadata: %{"workflow" => "settings_editor"}
               ]
           ) do
      {:ok, result(current, updated) |> Map.put(:target_version, target_version)}
    end
  end

  def rollback(_version, _params, _opts), do: {:error, :invalid_settings_rollback}

  defp sections(values) do
    Enum.map(@section_keys, fn {key, keys} ->
      {label, description} = Map.fetch!(@section_copy, key)

      %{
        key: Atom.to_string(key),
        label: label,
        description: description,
        fields: Enum.map(keys, &field(&1, values))
      }
    end)
  end

  defp field(key, values) do
    {:ok, definition} = Contract.definition(key)
    value = Map.fetch!(values, key)

    %{
      key: key,
      name: Atom.to_string(key),
      id: "setting-#{String.replace(Atom.to_string(key), "_", "-")}",
      label: Map.fetch!(@labels, key),
      input: input_type(definition),
      value: if(definition.storage == :encrypted_database, do: "", else: value),
      checked?: value == true,
      selected: if(is_list(value), do: value, else: []),
      options: options(definition),
      activation: definition.activation,
      activation_label: Map.fetch!(@activation_labels, definition.activation),
      validation: validation_label(definition),
      min: map_value(definition.validation, :min),
      max: map_value(definition.validation, :max),
      help: help_text(definition, value),
      secret_stored?: definition.storage == :encrypted_database and value == "[REDACTED]"
    }
  end

  defp parse_changes(params) do
    Enum.reduce_while(@editable_keys, {:ok, %{}}, fn key, {:ok, changes} ->
      {:ok, definition} = Contract.definition(key)
      raw = Map.get(params, Atom.to_string(key))

      case parse_value(definition, raw) do
        {:ok, :skip} -> {:cont, {:ok, changes}}
        {:ok, value} -> {:cont, {:ok, Map.put(changes, key, value)}}
        {:error, reason} -> {:halt, {:error, {:invalid_form_value, key, reason}}}
      end
    end)
  end

  defp parse_value(%{storage: :encrypted_database}, value) do
    case trimmed(value) do
      "" -> {:ok, :skip}
      text -> {:ok, text}
    end
  end

  defp parse_value(%{type: :boolean}, value), do: {:ok, truthy?(value)}

  defp parse_value(%{type: :integer}, value) do
    case Integer.parse(trimmed(value)) do
      {integer, ""} -> {:ok, integer}
      _error -> {:error, :not_an_integer}
    end
  end

  defp parse_value(%{type: {:list, :string}}, value) do
    values =
      value
      |> List.wrap()
      |> Enum.map(&trimmed/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    {:ok, values}
  end

  defp parse_value(%{type: type, validation: validation}, value)
       when type in [:string, :enum, :cron] do
    case trimmed(value) do
      "" ->
        if map_value(validation, :allow_nil, false), do: {:ok, nil}, else: {:error, :blank}

      text ->
        {:ok, text}
    end
  end

  defp parse_value(_definition, _value), do: {:error, :unsupported_type}

  defp confirmed_keys(params) do
    []
    |> maybe_confirm(:autonomy_mode, Map.get(params, "confirm_autonomous"))
    |> maybe_confirm(:mark_notifications_seen, Map.get(params, "confirm_notifications"))
  end

  defp maybe_confirm(keys, key, value) do
    if truthy?(value), do: [key | keys], else: keys
  end

  defp result(current, updated) do
    changed = changed_keys(current.values, updated.values)

    %{
      settings: updated,
      changed: Enum.map(changed, &Map.fetch!(@labels, &1)),
      activations:
        changed
        |> Enum.map(fn key ->
          {:ok, definition} = Contract.definition(key)

          %{
            key: definition.activation,
            label: Map.fetch!(@activation_labels, definition.activation)
          }
        end)
        |> Enum.uniq_by(& &1.key)
    }
  end

  defp changed_keys(before_values, after_values) do
    Enum.filter(@editable_keys, fn key ->
      Map.get(before_values, key) != Map.get(after_values, key)
    end)
  end

  defp changed_values(changes, current_values) do
    Map.reject(changes, fn {key, value} -> Map.get(current_values, key) == value end)
  end

  defp history(revisions, current_version) do
    revisions
    |> Enum.take(@history_limit)
    |> Enum.with_index()
    |> Enum.map(fn {revision, index} ->
      older = Enum.at(revisions, index + 1)
      values = map_value(revision, :values, %{})

      %{
        version: map_value(revision, :version),
        current?: map_value(revision, :version) == current_version,
        source: source_label(map_value(revision, :source)),
        inserted_at: date_time_iso8601(map_value(revision, :inserted_at)),
        inserted_label: date_time_label(map_value(revision, :inserted_at)),
        changed: revision_changes(values, older),
        confirms_autonomous?: Map.get(values, "autonomy_mode") == "autonomous",
        confirms_notifications?: Map.get(values, "mark_notifications_seen") == true
      }
    end)
  end

  defp revision_changes(_values, nil), do: ["Initial settings"]

  defp revision_changes(values, older) do
    previous = map_value(older, :values, %{})

    @editable_keys
    |> Enum.filter(fn key ->
      name = Atom.to_string(key)
      Map.get(values, name) != Map.get(previous, name)
    end)
    |> Enum.map(&Map.fetch!(@labels, &1))
    |> case do
      [] -> ["No recorded value changes"]
      changed -> changed
    end
  end

  defp activation_guide do
    [:immediate, :next_cycle, :session_reconnect, :worker_reconcile, :application_restart]
    |> Enum.map(&%{key: &1, label: Map.fetch!(@activation_labels, &1)})
  end

  defp input_type(%{storage: :encrypted_database}), do: :password
  defp input_type(%{type: :boolean}), do: :checkbox
  defp input_type(%{type: :integer}), do: :number
  defp input_type(%{type: :enum}), do: :select
  defp input_type(%{type: {:list, :string}}), do: :checkboxes
  defp input_type(%{type: :cron}), do: :cron
  defp input_type(_definition), do: :text

  defp options(%{type: :enum, validation: %{values: values}}),
    do: Enum.map(values, &%{value: &1, label: option_label(&1)})

  defp options(%{type: {:list, :string}, validation: %{values: values}}),
    do: Enum.map(values, &%{value: &1, label: option_label(&1)})

  defp options(_definition), do: []

  defp validation_label(%{type: :integer, validation: %{min: min, max: max}}),
    do: "Allowed range: #{min} to #{max}."

  defp validation_label(%{type: :cron}), do: "Use a valid five-part cron expression."

  defp validation_label(%{type: :enum, validation: %{values: values}}),
    do: "Allowed values: #{Enum.join(values, ", ")}."

  defp validation_label(%{type: {:list, :string}}),
    do: "Select only the listed actions."

  defp validation_label(%{validation: %{max_length: max}}),
    do: "Maximum length: #{max} characters."

  defp validation_label(_definition), do: nil

  defp help_text(%{storage: :encrypted_database}, value) do
    if value == "[REDACTED]",
      do: "A password is stored. Leave this field blank to keep it.",
      else: "The password is encrypted before it is saved."
  end

  defp help_text(%{key: :autonomy_mode}, _value),
    do: "Autonomous mode needs the separate confirmation below."

  defp help_text(%{key: :mark_notifications_seen}, _value),
    do: "Turning this on creates a remote protocol write and needs confirmation."

  defp help_text(%{activation: activation}, _value),
    do: "Activation: #{Map.fetch!(@activation_labels, activation)}."

  defp source_label("bootstrap"), do: "Initial setup"
  defp source_label("operator_console"), do: "Operator save"
  defp source_label("operator_console_rollback"), do: "Operator rollback"
  defp source_label("legacy_environment"), do: "Legacy environment import"

  defp source_label(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp option_label("observe"), do: "Observe only"
  defp option_label("review"), do: "Review before action"
  defp option_label("autonomous"), do: "Autonomous"
  defp option_label(value), do: value |> String.replace("_", " ") |> String.capitalize()

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) do
    case Integer.parse(trimmed(value)) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _error -> {:error, :invalid_settings_version}
    end
  end

  defp truthy?(values) when is_list(values), do: Enum.any?(values, &truthy?/1)
  defp truthy?(value), do: value in [true, "true", "1", "on", "yes"]

  defp trimmed(value) when is_binary(value), do: String.trim(value)
  defp trimmed(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp trimmed(_value), do: ""

  defp date_time_iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp date_time_iso8601(value), do: to_string(value || "")

  defp date_time_label(%DateTime{} = value), do: Calendar.strftime(value, "%b %d · %H:%M UTC")
  defp date_time_label(value), do: to_string(value || "Unknown time")

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default
end
