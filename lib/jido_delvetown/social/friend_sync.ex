defmodule JidoDelvetown.FriendSync do
  @moduledoc "Reads the account's follow collection into durable local friend memory."

  alias JidoDelvetown.{Config, FriendList, Protocol}

  @follow_collection "town.delve.graph.follow"
  @page_limit 100

  def sync(opts \\ []) do
    source = Keyword.get(opts, :source, Protocol)
    max_records = Keyword.get(opts, :max_records, Config.friend_sync_limit())

    with {:ok, page_result} <- fetch_follow_records(source, max_records),
         {:ok, dids} <- follow_dids(page_result.records),
         {actors, profile_errors} <- fetch_profiles(source, dids),
         {:ok, saved} <- FriendList.sync_following(actors) do
      {:ok,
       Map.merge(saved, %{
         pages: page_result.pages,
         records: length(page_result.records),
         profile_errors: profile_errors
       })}
    end
  end

  defp fetch_follow_records(source, max_records)
       when is_integer(max_records) and max_records > 0 do
    fetch_follow_records(source, nil, [], MapSet.new(), 0, max_records)
  end

  defp fetch_follow_records(_source, _max_records), do: {:error, :invalid_friend_sync_limit}

  defp fetch_follow_records(source, cursor, records, cursors, pages, max_records) do
    remaining = max_records - length(records)

    params =
      %{limit: min(@page_limit, remaining), reverse: true}
      |> maybe_put(:cursor, cursor)

    case source.list_own_records(@follow_collection, params) do
      {:ok, response} when is_map(response) ->
        with {:ok, page_records} <- response_records(response) do
          records = records ++ page_records
          next_cursor = value(response, :cursor)
          cursors = MapSet.put(cursors, cursor)
          pages = pages + 1

          cond do
            length(records) > max_records ->
              {:error, :friend_sync_limit_exceeded}

            next_cursor in [nil, ""] ->
              {:ok, %{records: records, pages: pages}}

            length(records) == max_records ->
              {:error, :friend_sync_limit_exceeded}

            MapSet.member?(cursors, next_cursor) ->
              {:error, :friend_sync_cursor_loop}

            true ->
              fetch_follow_records(
                source,
                next_cursor,
                records,
                cursors,
                pages,
                max_records
              )
          end
        end

      {:ok, _response} ->
        {:error, :invalid_follow_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp response_records(response) do
    case value(response, :records) do
      records when is_list(records) -> {:ok, records}
      _invalid -> {:error, :invalid_follow_response}
    end
  end

  defp follow_dids(records) do
    records
    |> Enum.reduce_while({:ok, MapSet.new()}, fn record, {:ok, dids} ->
      did = record |> value(:value) |> value(:subject)

      if valid_did?(did) do
        {:cont, {:ok, MapSet.put(dids, did)}}
      else
        {:halt, {:error, :invalid_follow_record}}
      end
    end)
    |> case do
      {:ok, dids} -> {:ok, dids |> MapSet.to_list() |> Enum.sort()}
      {:error, _reason} = error -> error
    end
  end

  defp fetch_profiles(source, dids) do
    Enum.map_reduce(dids, 0, fn did, error_count ->
      case source.query("town.delve.actor.getProfile", %{actor: did}) do
        {:ok, response} when is_map(response) ->
          {normalize_profile(response, did), error_count}

        _error ->
          {%{did: did}, error_count + 1}
      end
    end)
  end

  defp normalize_profile(response, did) do
    profile = value(response, :profile) || response

    %{
      did: did,
      handle: normalize_optional_text(value(profile, :handle)),
      display_name:
        normalize_optional_text(value(profile, :display_name) || value(profile, :displayName))
    }
  end

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp normalize_optional_text(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, item), do: Map.put(map, key, item)

  defp valid_did?("did:" <> rest), do: rest != ""
  defp valid_did?(_did), do: false

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp value(_value, _key), do: nil
end
