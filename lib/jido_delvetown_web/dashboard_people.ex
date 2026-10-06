defmodule JidoDelvetownWeb.DashboardPeople do
  @moduledoc false

  @count_keys ~w(known friends followers following mutuals excluded)a

  @spec build(map()) :: map()
  def build(inspection) do
    source = inspection_value(inspection, [:people], %{})
    records = list_value(source, :records)

    %{
      counts: normalized_counts(map_value(source, :counts, %{})),
      records: records,
      visible_count: count_value(source, :visible_count, length(records)),
      truncated?: map_value(source, :truncated?, false) == true
    }
  end

  defp normalized_counts(counts) do
    Map.new(@count_keys, &{&1, count_value(counts, &1, 0)})
  end

  defp count_value(map, key, default) do
    case map_value(map, key, default) do
      count when is_integer(count) and count >= 0 -> count
      _count -> default
    end
  end

  defp list_value(map, key) do
    case map_value(map, key, []) do
      list when is_list(list) -> list
      _list -> []
    end
  end

  defp inspection_value(value, [], _default), do: value

  defp inspection_value(value, [key | rest], default) when is_map(value) do
    value
    |> map_value(key, default)
    |> inspection_value(rest, default)
  end

  defp inspection_value(_value, _path, default), do: default

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default
end
