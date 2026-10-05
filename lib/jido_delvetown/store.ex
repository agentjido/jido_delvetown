defmodule JidoDelvetown.Store do
  @moduledoc "Durable SQLite state for the Delvetown agent."

  use GenServer

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{AuditEvent, Effect, InteractionEvent, ScanState}

  @notification_scan "notifications"
  @seen_kinds ["seen", "legacy_seen"]

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
    reserve_effect(key, collection, %{}, server)
  end

  def reserve_effect(key, collection, attributes, server)
      when is_binary(key) and is_binary(collection) and is_map(attributes) do
    GenServer.call(server, {:reserve_effect, key, collection, attributes})
  end

  def begin_effect_attempt(key, server \\ __MODULE__) do
    GenServer.call(server, {:begin_effect_attempt, key})
  end

  def complete_effect(key, receipt, server \\ __MODULE__) do
    GenServer.call(server, {:complete_effect, key, receipt})
  end

  def fail_effect_permanently(key, failure, server \\ __MODULE__) do
    GenServer.call(server, {:fail_effect_permanently, key, failure})
  end

  def add_event(type, data, server \\ __MODULE__) do
    GenServer.call(server, {:add_event, type, data})
  end

  def recent_events(server \\ __MODULE__, limit \\ 25) do
    GenServer.call(server, {:recent_events, limit})
  end

  @impl true
  def init(opts) do
    {:ok, %{repo: Keyword.get(opts, :repo, Repo)}}
  end

  @impl true
  def handle_call(:cursor, _from, state) do
    cursor =
      case state.repo.get(ScanState, @notification_scan) do
        %ScanState{cursor: cursor} -> cursor
        nil -> nil
      end

    {:reply, cursor, state}
  end

  def handle_call({:put_cursor, nil}, _from, state), do: {:reply, :ok, state}

  def handle_call({:put_cursor, cursor}, _from, state) when is_binary(cursor) do
    now = now()

    state.repo.insert_all(
      ScanState,
      [
        %{
          name: @notification_scan,
          cursor: cursor,
          metadata: %{},
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:cursor, :updated_at]},
      conflict_target: [:name]
    )

    {:reply, :ok, state}
  end

  def handle_call({:seen?, uri}, _from, state) do
    seen? =
      state.repo.exists?(
        from(event in InteractionEvent,
          where: event.record_uri == ^uri and event.kind in ^@seen_kinds
        )
      )

    {:reply, seen?, state}
  end

  def handle_call({:mark_seen, uri}, _from, state) do
    now = now()

    state.repo.insert_all(
      InteractionEvent,
      [
        %{
          event_key: seen_event_key(uri),
          kind: "seen",
          record_uri: uri,
          occurred_at: now,
          state: "completed",
          attempt_count: 0,
          payload: %{},
          terminal_at: now,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:event_key]
    )

    {:reply, :ok, state}
  end

  def handle_call({:effect, key}, _from, state) do
    {:reply, state.repo.get(Effect, key) |> effect_map(), state}
  end

  def handle_call({:reserve_effect, key, collection, attributes}, _from, state) do
    result =
      state.repo.transaction(
        fn ->
          case state.repo.get(Effect, key) do
            nil -> insert_reserved_effect(state.repo, key, collection, attributes)
            effect -> validate_reserved_effect(state.repo, effect, collection, attributes)
          end
        end,
        mode: :immediate
      )

    {:reply, transaction_result(result), state}
  end

  def handle_call({:begin_effect_attempt, key}, _from, state) do
    result =
      state.repo.transaction(
        fn ->
          case state.repo.get(Effect, key) do
            nil ->
              state.repo.rollback(:not_found)

            %Effect{status: status} = effect when status in ["reserved", "uncertain"] ->
              effect
              |> Ecto.Changeset.change(
                status: "uncertain",
                attempt_count: effect.attempt_count + 1,
                failure: nil
              )
              |> state.repo.update!()
              |> effect_map()

            %Effect{status: status} ->
              state.repo.rollback({:invalid_effect_state, status})
          end
        end,
        mode: :immediate
      )

    {:reply, transaction_result(result), state}
  end

  def handle_call({:complete_effect, key, receipt}, _from, state) do
    result =
      state.repo.transaction(
        fn ->
          case state.repo.get(Effect, key) do
            nil ->
              state.repo.rollback(:not_found)

            %Effect{status: "permanent_failure"} ->
              state.repo.rollback({:invalid_effect_state, "permanent_failure"})

            effect ->
              effect
              |> Ecto.Changeset.change(
                status: "completed",
                completed_at: now(),
                receipt: json_safe(receipt),
                failure: nil
              )
              |> state.repo.update!()
              |> effect_map()
          end
        end,
        mode: :immediate
      )

    {:reply, transaction_result(result), state}
  end

  def handle_call({:fail_effect_permanently, key, failure}, _from, state) do
    result =
      state.repo.transaction(
        fn ->
          case state.repo.get(Effect, key) do
            nil ->
              state.repo.rollback(:not_found)

            %Effect{status: "completed"} ->
              state.repo.rollback({:invalid_effect_state, "completed"})

            effect ->
              effect
              |> Ecto.Changeset.change(
                status: "permanent_failure",
                completed_at: now(),
                failure: json_safe(failure),
                receipt: nil
              )
              |> state.repo.update!()
              |> effect_map()
          end
        end,
        mode: :immediate
      )

    {:reply, transaction_result(result), state}
  end

  def handle_call({:add_event, type, data}, _from, state) do
    result =
      %AuditEvent{
        type: to_string(type),
        data: json_safe(data) || %{},
        occurred_at: now()
      }
      |> state.repo.insert()

    reply = if match?({:ok, _event}, result), do: :ok, else: result
    {:reply, reply, state}
  end

  def handle_call({:recent_events, limit}, _from, state) do
    events =
      state.repo.all(
        from(event in AuditEvent,
          order_by: [desc: event.id],
          limit: ^max(limit, 0)
        )
      )
      |> Enum.map(&audit_event_map/1)

    {:reply, events, state}
  end

  def handle_call(:counts, _from, state) do
    effects =
      state.repo.all(
        from(effect in Effect,
          group_by: effect.status,
          select: {effect.status, count()}
        )
      )

    counts =
      Enum.reduce(
        effects,
        %{
          reserved: 0,
          uncertain: 0,
          completed: 0,
          permanent_failure: 0,
          seen: seen_count(state.repo)
        },
        fn
          {"reserved", count}, acc -> %{acc | reserved: count}
          {"uncertain", count}, acc -> %{acc | uncertain: count}
          {"completed", count}, acc -> %{acc | completed: count}
          {"permanent_failure", count}, acc -> %{acc | permanent_failure: count}
          {_status, _count}, acc -> acc
        end
      )

    {:reply, counts, state}
  end

  defp insert_reserved_effect(repo, key, collection, attributes) do
    now = now()

    row = %{
      operation_key: key,
      kind: effect_kind(key),
      collection: collection,
      subject_key: attribute(attributes, :subject_key),
      actor_did: attribute(attributes, :actor_did),
      rkey: attribute(attributes, :rkey) || JidoDelvetown.Tid.generate(),
      status: "reserved",
      attempt_count: 0,
      reserved_at: now,
      inserted_at: now,
      updated_at: now
    }

    repo.insert_all(Effect, [row], on_conflict: :nothing, conflict_target: [:operation_key])
    repo.get!(Effect, key) |> effect_map()
  end

  defp validate_reserved_effect(repo, effect, collection, attributes) do
    expected_rkey = attribute(attributes, :rkey)

    cond do
      effect.collection != collection ->
        repo.rollback({:effect_conflict, :collection})

      is_binary(expected_rkey) and effect.rkey != expected_rkey ->
        repo.rollback({:effect_conflict, :rkey})

      true ->
        effect_map(effect)
    end
  end

  defp seen_count(repo) do
    repo.one(
      from(event in InteractionEvent,
        where: event.kind in ^@seen_kinds,
        select: count()
      )
    )
  end

  defp transaction_result({:ok, value}), do: {:ok, value}
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp effect_map(nil), do: nil

  defp effect_map(%Effect{} = effect) do
    %{
      key: effect.operation_key,
      kind: effect.kind,
      collection: effect.collection,
      subject_key: effect.subject_key,
      actor_did: effect.actor_did,
      rkey: effect.rkey,
      status: effect_status(effect.status),
      attempt_count: effect.attempt_count,
      created_at: iso8601(effect.reserved_at),
      completed_at: iso8601(effect.completed_at),
      receipt: effect.receipt,
      failure: effect.failure
    }
  end

  defp audit_event_map(%AuditEvent{} = event) do
    %{
      sequence: event.id,
      type: existing_atom(event.type),
      at: iso8601(event.occurred_at),
      data: existing_atom_keys(event.data)
    }
  end

  defp effect_status("reserved"), do: :reserved
  defp effect_status("uncertain"), do: :uncertain
  defp effect_status("completed"), do: :completed
  defp effect_status("complete"), do: :completed
  defp effect_status("permanent_failure"), do: :permanent_failure
  defp effect_status(status), do: status

  defp attribute(attributes, key),
    do: Map.get(attributes, key, Map.get(attributes, Atom.to_string(key)))

  defp effect_kind(key) do
    case String.split(key, ":", parts: 2) do
      [kind, _digest] -> kind
      _other -> "effect"
    end
  end

  defp seen_event_key(uri) do
    digest = :crypto.hash(:sha256, uri) |> Base.url_encode64(padding: false)
    "seen:" <> digest
  end

  defp json_safe(nil), do: nil
  defp json_safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%_{} = value), do: value |> Map.from_struct() |> json_safe()
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_safe(item)} end)
  end

  defp json_safe(value), do: inspect(value)

  defp existing_atom_keys(value) when is_list(value), do: Enum.map(value, &existing_atom_keys/1)

  defp existing_atom_keys(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {existing_atom(key), existing_atom_keys(item)} end)
  end

  defp existing_atom_keys(value), do: value

  defp existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp existing_atom(value), do: value

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
