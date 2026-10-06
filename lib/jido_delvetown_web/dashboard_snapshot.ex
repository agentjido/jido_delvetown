defmodule JidoDelvetownWeb.DashboardSnapshot do
  @moduledoc false

  alias JidoDelvetown.{Automation, Config, Personality}

  @page_title "AgentJido / DelveTown"

  @spec load(keyword()) :: map()
  def load(opts \\ []) do
    data_source = Keyword.get(opts, :data_source, JidoDelvetown)
    personality = Keyword.get(opts, :personality, Personality)
    review_controller = Keyword.get(opts, :review_controller, default_review_controller())
    config = Keyword.get(opts, :config, Config)
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() end) |> DateTime.truncate(:second)

    status_result = safe_read(fn -> data_source.status() end)
    status = value_or(status_result, %{})
    events_result = safe_read(fn -> data_source.recent_events(12) end)
    events = value_or(events_result, %{})
    inspection_result = safe_read(fn -> data_source.inspect_state(limit: 6) end)
    inspection = value_or(inspection_result, %{})
    character_result = safe_read(fn -> character_assigns(personality.character()) end)
    disclosure_result = safe_read(fn -> personality.disclosure() end)

    %{
      page_title: @page_title,
      status: status,
      status_error: error_text(status_result),
      operational_state: operational_state(status_result, status),
      budget: map_value(status, :budget, %{}),
      decision: map_value(status, :decision, %{}),
      last_cycle: map_value(status, :last_cycle, %{}),
      last_run: map_value(status, :last_run, %{}),
      workflow_events: list_value(events, :workflow),
      agent_events: list_value(events, :agent),
      inspection: inspection,
      inspection_error: error_text(inspection_result),
      character: value_or(character_result, unavailable_character()),
      disclosure: value_or(disclosure_result, %{}),
      reactive_review: review_status(review_controller, :reactive_review_status, :reactive),
      proactive_review: review_status(review_controller, :proactive_review_status, :proactive),
      manual_publish_enabled: config_value(config, :manual_publish_enabled?, false),
      port: config_value(config, :dashboard_port, 4040),
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

  defp config_value(config, function, default) do
    case safe_read(fn -> apply(config, function, []) end) do
      {:ok, value} -> value
      _result -> default
    end
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
end
