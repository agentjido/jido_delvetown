defmodule JidoDelvetownWeb.DashboardSnapshot do
  @moduledoc false

  alias JidoDelvetown.{Automation, Personality}
  alias JidoDelvetown.Settings.{Behavior, Connection, Console, Limits, Setup}
  alias JidoDelvetownWeb.DashboardOverview

  @page_title "AgentJido / DelveTown"

  @spec load(keyword()) :: map()
  def load(opts \\ []) do
    data_source = Keyword.get(opts, :data_source, JidoDelvetown)
    personality = Keyword.get(opts, :personality, Personality)
    review_controller = Keyword.get(opts, :review_controller, default_review_controller())
    behavior_settings = Keyword.get(opts, :behavior_settings, Behavior)
    connection_settings = Keyword.get(opts, :connection_settings, Connection)
    console_settings = Keyword.get(opts, :console_settings, Console)
    limits_settings = Keyword.get(opts, :limits_settings, Limits)
    setup_service = Keyword.get(opts, :setup_service, default_setup_service())
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() end) |> DateTime.truncate(:second)

    status_result = safe_read(fn -> data_source.status() end)
    status = value_or(status_result, %{})
    events_result = safe_read(fn -> data_source.recent_events(12) end)
    events = value_or(events_result, %{})
    inspection_result = safe_read(fn -> data_source.inspect_state(limit: 6) end)
    inspection = value_or(inspection_result, %{})
    character_result = safe_read(fn -> character_assigns(personality.character()) end)
    disclosure_result = safe_read(fn -> personality.disclosure() end)
    workflow_events = list_value(events, :workflow)
    agent_events = list_value(events, :agent)
    reactive_review = review_status(review_controller, :reactive_review_status, :reactive)
    proactive_review = review_status(review_controller, :proactive_review_status, :proactive)
    limits = settings_snapshot(limits_settings)

    overview =
      DashboardOverview.build(status, inspection, workflow_events, limits, now,
        status_error: error_text(status_result),
        reactive_review: reactive_review,
        proactive_review: proactive_review
      )

    %{
      page_title: @page_title,
      status: status,
      status_error: error_text(status_result),
      operational_state: operational_state(status_result, status),
      budget: map_value(status, :budget, %{}),
      decision: map_value(status, :decision, %{}),
      last_cycle: map_value(status, :last_cycle, %{}),
      last_run: map_value(status, :last_run, %{}),
      workflow_events: workflow_events,
      agent_events: agent_events,
      inspection: inspection,
      inspection_error: error_text(inspection_result),
      character: value_or(character_result, unavailable_character()),
      disclosure: value_or(disclosure_result, %{}),
      reactive_review: reactive_review,
      proactive_review: proactive_review,
      overview: overview,
      theme: setting_value(console_settings, :theme, "system"),
      setup: setup_status(setup_service),
      manual_publish_enabled: direct_value(behavior_settings, :manual_publish_enabled?, false),
      port: dashboard_port(connection_settings),
      refreshed_at: DateTime.to_iso8601(now),
      refreshed_label: Calendar.strftime(now, "%H:%M:%S UTC")
    }
  end

  defp character_assigns(character) do
    contract = character.extensions.delvetown

    %{
      name: character.name,
      mission: contract.mission,
      traits: character.personality.traits,
      topical_scope: contract.topical_scope
    }
  end

  defp unavailable_character do
    %{name: "AgentJido", mission: "Character data is unavailable.", traits: [], topical_scope: []}
  end

  defp review_status(controller, function, kind) do
    case safe_read(fn -> apply(controller, function, []) end) do
      {:ok, status} when is_map(status) -> status
      _result -> unavailable_review(kind)
    end
  end

  defp unavailable_review(kind) do
    %{
      status: :failed,
      label: "Runtime unavailable",
      detail: "Start the Agent and Oban runtimes before you run a #{kind} review.",
      disabled?: true,
      job_id: nil
    }
  end

  defp direct_value(service, function, default) do
    case safe_read(fn -> apply(service, function, []) end) do
      {:ok, value} -> value
      _result -> default
    end
  end

  defp dashboard_port(connection_settings) do
    case safe_read(fn -> apply(connection_settings, :dashboard, []) end) do
      {:ok, {:ok, dashboard}} when is_map(dashboard) ->
        case map_value(dashboard, :port, 4040) do
          port when is_integer(port) and port > 0 -> port
          _port -> 4040
        end

      _result ->
        4040
    end
  end

  defp setting_value(settings, function, default) do
    case safe_read(fn -> apply(settings, function, []) end) do
      {:ok, {:ok, value}} -> value
      _result -> default
    end
  end

  defp settings_snapshot(settings) do
    case safe_read(fn -> apply(settings, :current, []) end) do
      {:ok, {:ok, value}} when is_map(value) -> value
      _result -> %{}
    end
  end

  defp setup_status(service) do
    case safe_read(fn -> apply(service, :status, []) end) do
      {:ok, {:ok, status}} when is_map(status) -> Map.put(status, :available?, true)
      {:error, reason} -> unavailable_setup(reason)
      _result -> unavailable_setup(:invalid_setup_status)
    end
  end

  defp unavailable_setup(reason) do
    %{
      available?: false,
      required?: false,
      identifier: "",
      password_configured?: false,
      decision_model: "openai:gpt-4o-mini",
      model_options: Setup.model_options(),
      autonomy_mode: "observe",
      autonomy_options: Setup.safe_autonomy_options(),
      llm_key: %{provider: "OpenAI", environment: "OPENAI_API_KEY", configured?: false},
      settings_version: 1,
      error: inspect(reason, pretty: true, limit: 20)
    }
  end

  defp safe_read(fun) do
    case fun.() do
      {:error, reason} -> {:error, reason}
      value -> {:ok, value}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp value_or({:ok, value}, _default) when is_map(value), do: value
  defp value_or(_result, default), do: default

  defp error_text({:error, reason}), do: inspect(reason, pretty: true, limit: 20)
  defp error_text(_result), do: nil

  defp operational_state({:error, _reason}, _status) do
    %{
      key: "attention",
      label: "Needs attention",
      effect: "The Agent runtime is unavailable. Scheduled work cannot run.",
      next: "Start the local runtime and wait for the next refresh."
    }
  end

  defp operational_state(_result, status) do
    cond do
      map_value(status, :writes_enabled?, false) ->
        %{
          key: "active",
          label: "Writes enabled",
          effect: "Scheduled Agent work can create public protocol effects.",
          next: "Use the review path before any future one-click action."
        }

      map_value(status, :dry_run_mark_actioned?, false) ->
        %{
          key: "safe",
          label: "Dry run: actions simulated",
          effect: "Protocol effects are blocked. Selected actions advance local dry-run memory.",
          next: "A simulated action is not published and will not run again."
        }

      true ->
        %{
          key: "safe",
          label: "Safe: writes off",
          effect: "Protocol effects are blocked. Review cycles can inspect and propose.",
          next: nil
        }
    end
  end

  defp list_value(map, key) do
    case map_value(map, key, []) do
      value when is_list(value) -> value
      _value -> []
    end
  end

  defp map_value(map, key, default)

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_value(_value, _key, default), do: default

  defp default_review_controller do
    Application.get_env(:jido_delvetown, :reactive_review_controller, Automation)
  end

  defp default_setup_service do
    Application.get_env(:jido_delvetown, :setup_service, Setup)
  end
end
