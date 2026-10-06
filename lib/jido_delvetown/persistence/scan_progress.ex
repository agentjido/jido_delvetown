defmodule JidoDelvetown.ScanProgress do
  @moduledoc "Durable cursors and leases for bounded protocol scans."

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.ScanState

  @default_lease_ms 5 * 60 * 1_000

  def claim(name, opts \\ []) when is_binary(name) and name != "" do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, now())
    lease_ms = Keyword.get(opts, :lease_ms, @default_lease_ms)

    repo.transaction(
      fn ->
        state = repo.get(ScanState, name) || insert_state(repo, name, now)
        metadata = state.metadata || %{}

        if active_lease?(metadata, now) do
          repo.rollback(:scan_in_progress)
        else
          token = token()
          lease_until = DateTime.add(now, lease_ms, :millisecond)

          metadata =
            metadata
            |> Map.put("lease_token", token)
            |> Map.put("lease_until", DateTime.to_iso8601(lease_until))
            |> Map.put("claimed_at", DateTime.to_iso8601(now))

          state
          |> Ecto.Changeset.change(metadata: metadata)
          |> repo.update!()

          %{name: name, cursor: state.cursor, token: token, lease_until: lease_until}
        end
      end,
      mode: :immediate
    )
    |> transaction_result()
  end

  def finish(name, token, cursor, opts \\ [])
      when is_binary(name) and is_binary(token) and (is_binary(cursor) or is_nil(cursor)) do
    update_claim(name, token, opts, fn state, metadata, current_time ->
      metadata =
        metadata
        |> clear_lease()
        |> Map.put("last_completed_at", DateTime.to_iso8601(current_time))

      Ecto.Changeset.change(state, cursor: cursor, metadata: metadata)
    end)
  end

  def release(name, token, opts \\ []) when is_binary(name) and is_binary(token) do
    update_claim(name, token, opts, fn state, metadata, current_time ->
      metadata =
        metadata
        |> clear_lease()
        |> Map.put("last_released_at", DateTime.to_iso8601(current_time))

      Ecto.Changeset.change(state, metadata: metadata)
    end)
  end

  def get(name, opts \\ []) when is_binary(name) do
    case Keyword.get(opts, :repo, Repo).get(ScanState, name) do
      nil -> nil
      state -> scan_map(state)
    end
  end

  def put_cursor(name, cursor, opts \\ [])
      when is_binary(name) and (is_binary(cursor) or is_nil(cursor)) do
    repo = Keyword.get(opts, :repo, Repo)
    current_time = Keyword.get(opts, :now, now())

    repo.transaction(
      fn ->
        state = repo.get(ScanState, name) || insert_state(repo, name, current_time)

        state
        |> Ecto.Changeset.change(cursor: cursor)
        |> repo.update!()
        |> scan_map()
      end,
      mode: :immediate
    )
    |> transaction_result()
  end

  defp update_claim(name, token, opts, changes) do
    repo = Keyword.get(opts, :repo, Repo)
    current_time = Keyword.get(opts, :now, now())

    repo.transaction(
      fn ->
        case repo.get(ScanState, name) do
          nil ->
            repo.rollback(:scan_not_found)

          state ->
            metadata = state.metadata || %{}

            if metadata["lease_token"] == token do
              state
              |> changes.(metadata, current_time)
              |> repo.update!()
              |> scan_map()
            else
              repo.rollback(:stale_scan_claim)
            end
        end
      end,
      mode: :immediate
    )
    |> transaction_result()
  end

  defp insert_state(repo, name, current_time) do
    %ScanState{
      name: name,
      cursor: nil,
      metadata: %{},
      inserted_at: current_time,
      updated_at: current_time
    }
    |> repo.insert!()
  end

  defp active_lease?(%{"lease_until" => lease_until}, current_time)
       when is_binary(lease_until) do
    case DateTime.from_iso8601(lease_until) do
      {:ok, time, _offset} -> DateTime.compare(time, current_time) == :gt
      _invalid -> false
    end
  end

  defp active_lease?(_metadata, _current_time), do: false

  defp clear_lease(metadata),
    do: Map.drop(metadata, ["lease_token", "lease_until", "claimed_at"])

  defp scan_map(state) do
    %{
      name: state.name,
      cursor: state.cursor,
      metadata: state.metadata || %{},
      updated_at: state.updated_at
    }
  end

  defp transaction_result({:ok, value}), do: {:ok, value}
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp token do
    18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
