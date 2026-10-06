defmodule JidoDelvetownWeb.DashboardActivity do
  @moduledoc false

  @filters ~w(all actions publications failures jobs settings)
  @failure_states ~w(error failed permanent_failure retryable discarded cancelled uncertain)

  @spec build([map()], map(), map()) :: map()
  def build(workflow_events, inspection, settings_editor) do
    items =
      action_items(workflow_events) ++
        publication_items(inspection) ++
        effect_failure_items(inspection) ++
        job_items(inspection) ++
        settings_items(settings_editor)

    items = Enum.sort_by(items, &{sort_time(&1), &1.id}, :desc)

    %{
      items: items,
      counts: %{
        "all" => length(items),
        "actions" => category_count(items, "actions"),
        "publications" => category_count(items, "publications"),
        "failures" => Enum.count(items, &(map_value(&1, :failure?, false) == true)),
        "jobs" => category_count(items, "jobs"),
        "settings" => category_count(items, "settings")
      }
    }
  end

  @spec normalize_filter(term()) :: String.t()
  def normalize_filter(filter) when filter in @filters, do: filter
  def normalize_filter(_filter), do: "all"

  @spec filtered_items(map(), term()) :: [map()]
  def filtered_items(activity, filter) do
    items = list_value(activity, :items)

    case normalize_filter(filter) do
      "all" -> items
      "failures" -> Enum.filter(items, &(map_value(&1, :failure?, false) == true))
      category -> Enum.filter(items, &(map_value(&1, :category) == category))
    end
  end

  defp action_items(events) when is_list(events), do: Enum.map(events, &action_item/1)
  defp action_items(_events), do: []

  defp action_item(event) do
    type = event |> map_value(:type, "activity") |> text_value("activity")
    data = map_value(event, :data, %{})
    status = action_status(data)
    at = map_value(event, :at)

    %{
      id: "audit:#{map_value(event, :sequence, "#{type}:#{at}")}",
      category: "actions",
      label: "Action",
      title: action_title(type, data),
      status: status,
      detail: action_detail(type, data),
      at: at,
      uri: action_uri(data),
      cid: nil,
      failure?: failure_state?(status)
    }
  end

  defp publication_items(inspection) do
    inspection
    |> inspection_list([:effects, :completed_receipts])
    |> Enum.map(fn receipt ->
      kind = receipt |> map_value(:kind, "protocol") |> text_value("protocol")
      operation_key = map_value(receipt, :operation_key, "effect")
      receipt_data = map_value(receipt, :receipt, %{})

      %{
        id: "receipt:#{operation_key}",
        category: "publications",
        label: "Publication receipt",
        title: "#{humanize(kind)} effect completed",
        status: map_value(receipt, :status, "completed") |> text_value("completed"),
        detail: publication_detail(receipt),
        at: map_value(receipt, :completed_at),
        uri: map_value(receipt_data, :uri),
        cid: map_value(receipt_data, :cid),
        failure?: false
      }
    end)
  end

  defp effect_failure_items(inspection) do
    inspection
    |> inspection_list([:effects, :attention])
    |> Enum.map(fn effect ->
      status = effect |> map_value(:status, "attention") |> text_value("attention")
      kind = effect |> map_value(:kind, "protocol") |> text_value("protocol")
      operation_key = map_value(effect, :operation_key, "effect")

      %{
        id: "failure:#{operation_key}",
        category: "failures",
        label: "Failure and recovery",
        title: "#{humanize(kind)} effect needs attention",
        status: status,
        detail:
          "#{operation_key} · attempt #{non_negative_integer(map_value(effect, :attempt_count))}",
        at: map_value(effect, :completed_at) || map_value(effect, :reserved_at),
        uri: nil,
        cid: nil,
        failure?: true
      }
    end)
  end

  defp job_items(inspection) do
    inspection
    |> inspection_list([:automation, :recent_jobs])
    |> Enum.map(fn job ->
      state = job |> map_value(:state, "unknown") |> text_value("unknown")
      id = map_value(job, :id, "unknown")

      %{
        id: "job:#{id}",
        category: "jobs",
        label: "Oban job",
        title: worker_label(map_value(job, :worker)),
        status: state,
        detail:
          "#{map_value(job, :queue, "unknown")} queue · attempt #{non_negative_integer(map_value(job, :attempt))}/#{non_negative_integer(map_value(job, :max_attempts))} · #{non_negative_integer(map_value(job, :error_count))} errors",
        at: job_time(job),
        uri: nil,
        cid: nil,
        failure?: failure_state?(state)
      }
    end)
  end

  defp settings_items(settings_editor) do
    settings_editor
    |> list_value(:history)
    |> Enum.map(fn revision ->
      version = map_value(revision, :version, "unknown")
      current? = map_value(revision, :current?, false) == true

      %{
        id: "settings:#{version}",
        category: "settings",
        label: "Configuration revision",
        title: "Runtime settings v#{version}",
        status: if(current?, do: "current", else: "recorded"),
        detail: settings_detail(revision),
        at: map_value(revision, :inserted_at),
        uri: nil,
        cid: nil,
        failure?: false
      }
    end)
  end

  defp action_status(data) do
    (map_value(data, :cycle_status) || map_value(data, :result) || map_value(data, :status) ||
       "recorded")
    |> text_value("recorded")
  end

  defp action_title("decision", data) do
    data
    |> map_value(:action, "participation")
    |> text_value("participation")
    |> humanize()
  end

  defp action_title("create_record", _data), do: "Published record"
  defp action_title("delete_record", _data), do: "Deleted record"
  defp action_title("manual_publish", _data), do: "Manual publication"
  defp action_title("upload_blob", _data), do: "Uploaded media"
  defp action_title(type, _data), do: humanize(type)

  defp action_detail("decision", data) do
    map_value(data, :model_reason) || map_value(data, :candidate_id) || "Decision recorded."
  end

  defp action_detail(_type, data) do
    map_value(data, :event_key) || map_value(data, :rkey) || map_value(data, :collection) ||
      map_value(data, :method) || "Audit event recorded."
  end

  defp action_uri(data) do
    map_value(data, :record_uri) || map_value(data, :uri) || map_value(data, :target_uri)
  end

  defp publication_detail(receipt) do
    collection = map_value(receipt, :collection)
    operation_key = map_value(receipt, :operation_key, "effect")

    if present_text?(collection), do: "#{collection} · #{operation_key}", else: operation_key
  end

  defp settings_detail(revision) do
    changed = list_value(revision, :changed)
    source = map_value(revision, :source, "Recorded change")

    case changed do
      [] -> source
      fields -> "#{source} · #{Enum.join(fields, " · ")}"
    end
  end

  defp worker_label(worker) do
    worker
    |> text_value("Unknown worker")
    |> String.split(".")
    |> List.last()
    |> humanize()
  end

  defp job_time(job) do
    map_value(job, :completed_at) || map_value(job, :discarded_at) ||
      map_value(job, :cancelled_at) || map_value(job, :attempted_at) ||
      map_value(job, :scheduled_at) || map_value(job, :inserted_at)
  end

  defp failure_state?(state), do: state in @failure_states

  defp category_count(items, category),
    do: Enum.count(items, &(map_value(&1, :category) == category))

  defp sort_time(item), do: map_value(item, :at, "") || ""

  defp inspection_list(value, []), do: if(is_list(value), do: value, else: [])

  defp inspection_list(value, [key | rest]) when is_map(value) do
    value
    |> map_value(key, [])
    |> inspection_list(rest)
  end

  defp inspection_list(_value, _path), do: []

  defp list_value(map, key) do
    case map_value(map, key, []) do
      list when is_list(list) -> list
      _value -> []
    end
  end

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value), do: 0

  defp text_value(value, _default) when is_binary(value), do: value
  defp text_value(value, _default) when is_atom(value), do: Atom.to_string(value)
  defp text_value(_value, default), do: default

  defp present_text?(value), do: is_binary(value) and String.trim(value) != ""

  defp humanize(value) do
    value
    |> text_value("Activity")
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.replace(["_", "-", "."], " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default
end
