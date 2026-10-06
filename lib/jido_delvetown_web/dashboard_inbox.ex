defmodule JidoDelvetownWeb.DashboardInbox do
  @moduledoc false

  @categories [
    {"reply", "Replies"},
    {"mention", "Mentions"},
    {"follow", "Follows"},
    {"like", "Likes"}
  ]

  @actionable_states ["pending", "claimed", "failed"]

  @spec build(map()) :: map()
  def build(inspection) do
    events = inspection_list(inspection, [:events, :recent])

    %{
      events: events,
      categories: categories(events),
      actionable_count: Enum.count(events, &(map_value(&1, :state) in @actionable_states)),
      proposal_count: Enum.count(events, &is_map(map_value(&1, :proposal))),
      last_scan: last_notification_scan(inspection)
    }
  end

  defp categories(events) do
    Enum.map(@categories, fn {key, label} ->
      %{
        key: key,
        label: label,
        count: Enum.count(events, &(map_value(&1, :kind) == key))
      }
    end)
  end

  defp last_notification_scan(inspection) do
    inspection
    |> inspection_list([:scans])
    |> Enum.find(&(map_value(&1, :name) == "notifications"))
  end

  defp inspection_list(value, path) do
    case inspection_value(value, path, []) do
      list when is_list(list) -> list
      _value -> []
    end
  end

  defp inspection_value(value, [], _default), do: value

  defp inspection_value(value, [key | rest], default) when is_map(value) do
    value
    |> map_value(key, default)
    |> inspection_value(rest, default)
  end

  defp inspection_value(_value, _path, default), do: default

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default
end
