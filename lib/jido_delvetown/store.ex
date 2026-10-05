defmodule JidoDelvetown.Store do
  @moduledoc "Durable local effect keys and audit events for the Delvetown agent."

  use GenServer

  alias JidoDelvetown.Config

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def cursor(server \\ __MODULE__), do: GenServer.call(server, :cursor)
  def put_cursor(cursor, server \\ __MODULE__), do: GenServer.call(server, {:put_cursor, cursor})
  def seen?(uri, server \\ __MODULE__), do: GenServer.call(server, {:seen?, uri})
  def mark_seen(uri, server \\ __MODULE__), do: GenServer.call(server, {:mark_seen, uri})
  def effect(key, server \\ __MODULE__), do: GenServer.call(server, {:effect, key})
  def counts(server \\ __MODULE__), do: GenServer.call(server, :counts)

  def reserve_effect(key, collection, server \\ __MODULE__) do
    GenServer.call(server, {:reserve_effect, key, collection})
  end

  def complete_effect(key, receipt, server \\ __MODULE__) do
    GenServer.call(server, {:complete_effect, key, receipt})
  end

  def add_event(type, data, server \\ __MODULE__) do
    GenServer.call(server, {:add_event, type, data})
  end

  def recent_events(server \\ __MODULE__, limit \\ 25) do
    GenServer.call(server, {:recent_events, limit})
  end

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path, Config.state_path())
    table = Keyword.get(opts, :table, __MODULE__)
    :ok = path |> Path.dirname() |> File.mkdir_p()

    case :dets.open_file(table, file: String.to_charlist(path), type: :set, auto_save: 500) do
      {:ok, ^table} -> {:ok, %{table: table}}
      {:error, reason} -> {:stop, {:dets_open_failed, reason}}
    end
  end

  @impl true
  def handle_call(:cursor, _from, state), do: {:reply, lookup(state.table, :cursor), state}
  def handle_call({:put_cursor, nil}, _from, state), do: {:reply, :ok, state}

  def handle_call({:put_cursor, cursor}, _from, state) when is_binary(cursor) do
    {:reply, insert(state.table, {:cursor, cursor}), state}
  end

  def handle_call({:seen?, uri}, _from, state) do
    {:reply, :dets.member(state.table, {:seen, uri}), state}
  end

  def handle_call({:mark_seen, uri}, _from, state) do
    {:reply, insert(state.table, {{:seen, uri}, %{uri: uri, seen_at: now()}}), state}
  end

  def handle_call({:effect, key}, _from, state) do
    {:reply, lookup(state.table, {:effect, key}), state}
  end

  def handle_call({:reserve_effect, key, collection}, _from, state) do
    case lookup(state.table, {:effect, key}) do
      nil ->
        effect = %{
          key: key,
          collection: collection,
          rkey: JidoDelvetown.Tid.generate(),
          status: :reserved,
          created_at: now(),
          completed_at: nil,
          receipt: nil
        }

        :ok = insert(state.table, {{:effect, key}, effect})
        {:reply, {:ok, effect}, state}

      effect ->
        {:reply, {:ok, effect}, state}
    end
  end

  def handle_call({:complete_effect, key, receipt}, _from, state) do
    case lookup(state.table, {:effect, key}) do
      nil ->
        {:reply, {:error, :not_found}, state}

      effect ->
        updated = %{effect | status: :complete, completed_at: now(), receipt: receipt}
        :ok = insert(state.table, {{:effect, key}, updated})
        {:reply, {:ok, updated}, state}
    end
  end

  def handle_call({:add_event, type, data}, _from, state) do
    sequence = System.unique_integer([:monotonic, :positive])
    event = %{type: type, at: now(), data: data}
    {:reply, insert(state.table, {{:event, sequence}, event}), state}
  end

  def handle_call({:recent_events, limit}, _from, state) do
    events =
      fold(state.table, [], fn
        {{:event, sequence}, event}, acc -> [Map.put(event, :sequence, sequence) | acc]
        _entry, acc -> acc
      end)
      |> Enum.sort_by(& &1.sequence, :desc)
      |> Enum.take(limit)

    {:reply, events, state}
  end

  def handle_call(:counts, _from, state) do
    counts =
      fold(state.table, %{reserved: 0, complete: 0, seen: 0}, fn
        {{:effect, _key}, %{status: status}}, acc when is_map_key(acc, status) ->
          Map.update!(acc, status, &(&1 + 1))

        {{:seen, _uri}, _seen}, acc ->
          Map.update!(acc, :seen, &(&1 + 1))

        _entry, acc ->
          acc
      end)

    {:reply, counts, state}
  end

  @impl true
  def terminate(_reason, state) do
    :dets.sync(state.table)
    :dets.close(state.table)
  end

  defp lookup(table, key) do
    case :dets.lookup(table, key) do
      [{^key, item}] -> item
      [] -> nil
    end
  end

  defp insert(table, entry) do
    case :dets.insert(table, entry) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp fold(table, initial, reducer), do: :dets.foldl(reducer, initial, table)
  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
