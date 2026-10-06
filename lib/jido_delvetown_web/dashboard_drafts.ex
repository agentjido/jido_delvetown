defmodule JidoDelvetownWeb.DashboardDrafts do
  @moduledoc false

  @spec build(map()) :: map()
  def build(inspection) do
    text = list_value(inspection, :simulated_posts)
    likes = list_value(inspection, :like_proposals)
    images = list_value(inspection, :image_drafts)
    items = classify(text, :text) ++ classify(likes, :like) ++ classify(images, :image)

    %{
      total_count: length(items),
      pending_count: count_state(items, "pending"),
      approved_count: count_state(items, "approved"),
      rejected_count: count_state(items, "rejected"),
      published_count: count_state(items, "published"),
      type_counts: %{
        text: length(text),
        like: length(likes),
        image: length(images)
      }
    }
  end

  defp classify(items, kind) do
    Enum.map(items, fn item -> %{kind: kind, state: item_state(item, kind)} end)
  end

  defp item_state(item, :text) do
    if map_value(item, :published_status) == "completed",
      do: "published",
      else: review_state(item)
  end

  defp item_state(item, kind) when kind in [:like, :image] do
    if map_value(item, :publication_state) == "published",
      do: "published",
      else: review_state(item)
  end

  defp review_state(item) do
    item
    |> map_value(:review, %{})
    |> map_value(:state, "pending")
  end

  defp count_state(items, state), do: Enum.count(items, &(&1.state == state))

  defp list_value(map, key) do
    case map_value(map, key, []) do
      value when is_list(value) -> value
      _value -> []
    end
  end

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default
end
