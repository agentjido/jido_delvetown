defmodule JidoDelvetown.InteractionEvents do
  @moduledoc "Owns durable interaction event identity, state transitions, and retention."

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{Effect, InteractionEvent}

  @terminal_states ["completed", "ignored", "failed"]
  @default_retention_days 90
  @default_event_limit 5_000

  def event_key(kind, values) when is_binary(kind) and is_list(values) do
    digest =
      values
      |> Enum.map(&key_part/1)
      |> Enum.intersperse(<<0>>)
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    kind <> ":" <> digest
  end

  def observe_candidates(candidates, opts \\ []) when is_list(candidates) do
    Enum.reduce_while(candidates, :ok, fn candidate, :ok ->
      attrs = %{
        event_key: candidate.event_key,
        kind: candidate.reason,
        actor_did: get_in(candidate, [:author, :did]),
        record_uri: Map.get(candidate, :target_uri) || candidate.uri,
        source_id: candidate.protocol_id || candidate.id,
        occurred_at: candidate.indexed_at,
        payload: %{
          protocol_id: Map.get(candidate, :protocol_id),
          notification_id: Map.get(candidate, :protocol_id),
          notification_uri: Map.get(candidate, :uri),
          notification_cid: Map.get(candidate, :cid),
          raw_reason: Map.get(candidate, :raw_reason),
          reason_subject: Map.get(candidate, :reason_subject),
          target_uri: Map.get(candidate, :target_uri),
          target_cid: Map.get(candidate, :target_cid),
          joined_at: Map.get(candidate, :joined_at)
        }
      }

      case observe(attrs, opts) do
        {:ok, _event} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def observe(attrs, opts \\ []) when is_map(attrs) do
    repo = repo(opts)
    now = now()
    occurred_at = parse_time(Map.get(attrs, :occurred_at) || Map.get(attrs, "occurred_at"))

    row = %{
      event_key: fetch!(attrs, :event_key),
      kind: fetch!(attrs, :kind),
      actor_did: value(attrs, :actor_did),
      record_uri: value(attrs, :record_uri),
      source_id: value(attrs, :source_id),
      occurred_at: occurred_at,
      state: "pending",
      attempt_count: 0,
      payload: json_safe(value(attrs, :payload, %{})),
      inserted_at: now,
      updated_at: now
    }

    conflict_query =
      from(event in InteractionEvent,
        update: [
          set: [
            kind: fragment("EXCLUDED.kind"),
            actor_did: fragment("EXCLUDED.actor_did"),
            record_uri: fragment("EXCLUDED.record_uri"),
            source_id: fragment("EXCLUDED.source_id"),
            occurred_at: fragment("EXCLUDED.occurred_at"),
            payload: fragment("EXCLUDED.payload"),
            updated_at: fragment("EXCLUDED.updated_at")
          ]
        ],
        where: event.state == "pending"
      )

    repo.insert_all(
      InteractionEvent,
      [row],
      on_conflict: conflict_query,
      conflict_target: [:event_key]
    )

    {:ok, repo.get!(InteractionEvent, row.event_key)}
  rescue
    error -> {:error, {:observe_failed, Exception.message(error)}}
  end

  def claim(event_key, opts \\ []) when is_binary(event_key) do
    repo = repo(opts)
    claimed_at = now()

    {count, _rows} =
      repo.update_all(
        from(event in InteractionEvent,
          where: event.event_key == ^event_key and event.state == "pending"
        ),
        set: [state: "claimed", claimed_at: claimed_at, updated_at: claimed_at],
        inc: [attempt_count: 1]
      )

    case {count, repo.get(InteractionEvent, event_key)} do
      {1, %InteractionEvent{} = event} -> {:ok, event}
      {0, nil} -> {:error, :not_found}
      {0, %InteractionEvent{state: state}} -> {:error, {:not_claimable, state}}
    end
  end

  def finish(event_key, outcome, details \\ %{}, opts \\ [])
      when is_binary(event_key) and outcome in [:completed, :ignored, :failed] and
             is_map(details) do
    repo = repo(opts)
    terminal_at = now()
    state = Atom.to_string(outcome)
    failure = if outcome == :failed, do: json_safe(details), else: nil

    {count, _rows} =
      repo.update_all(
        from(event in InteractionEvent,
          where: event.event_key == ^event_key and event.state == "claimed"
        ),
        set: [
          state: state,
          failure: failure,
          terminal_at: terminal_at,
          updated_at: terminal_at
        ]
      )

    case {count, repo.get(InteractionEvent, event_key)} do
      {1, %InteractionEvent{} = event} -> {:ok, event}
      {0, nil} -> {:error, :not_found}
      {0, %InteractionEvent{state: current}} -> {:error, {:invalid_transition, current, state}}
    end
  end

  def recover_stale_claims(opts \\ []) do
    repo = repo(opts)
    stale_after_ms = Keyword.get(opts, :stale_after_ms, 5 * 60 * 1_000)
    cutoff = DateTime.add(now(), -stale_after_ms, :millisecond)
    recovered_at = now()

    {count, _rows} =
      repo.update_all(
        from(event in InteractionEvent,
          where: event.state == "claimed" and event.claimed_at <= ^cutoff
        ),
        set: [state: "pending", claimed_at: nil, updated_at: recovered_at]
      )

    {:ok, count}
  end

  def get(event_key, opts \\ []), do: repo(opts).get(InteractionEvent, event_key)

  def record_manual_publication(event_key, details, opts \\ [])
      when is_binary(event_key) and is_map(details) do
    repo = repo(opts)

    case repo.get(InteractionEvent, event_key) do
      nil ->
        {:error, :not_found}

      event ->
        payload = Map.put(event.payload || %{}, "manual_publication", json_safe(details))

        event
        |> Ecto.Changeset.change(payload: payload, updated_at: now())
        |> repo.update()
    end
  end

  def processable?(event_key, opts \\ []) when is_binary(event_key) do
    case get(event_key, opts) do
      nil -> true
      %InteractionEvent{state: "pending"} -> true
      %InteractionEvent{} -> false
    end
  end

  def pending?(kinds, opts \\ []) when is_list(kinds) do
    repo(opts).exists?(
      from(event in InteractionEvent,
        where: event.state == "pending" and event.kind in ^kinds
      )
    )
  end

  def all_terminal?(candidates, opts \\ []) when is_list(candidates) do
    keys = Enum.map(candidates, & &1.event_key)

    terminal_count =
      repo(opts).aggregate(
        from(event in InteractionEvent,
          where: event.event_key in ^keys and event.state in ^@terminal_states
        ),
        :count,
        :event_key
      )

    terminal_count == length(Enum.uniq(keys))
  end

  def outreach_count(kind, since, opts \\ [])
      when is_binary(kind) and is_struct(since, DateTime) do
    repo = repo(opts)
    excluded_event_key = Keyword.get(opts, :exclude_event_key)

    effects =
      repo.aggregate(
        from(effect in Effect,
          where:
            effect.kind == ^kind and effect.status in ["reserved", "uncertain", "completed"] and
              effect.reserved_at >= ^since
        ),
        :count,
        :operation_key
      )

    simulation_query =
      from(event in InteractionEvent,
        where:
          event.state == "completed" and event.terminal_at >= ^since and
            fragment("json_extract(?, '$.cycle_status')", event.payload) == "simulated" and
            fragment("json_extract(?, '$.action')", event.payload) == ^kind and
            fragment(
              "coalesce(json_extract(?, '$.manual_publication.status'), '') != 'completed'",
              event.payload
            )
      )

    simulation_query = exclude_event(simulation_query, excluded_event_key)
    simulations = repo.aggregate(simulation_query, :count, :event_key)

    effects + simulations
  end

  def recent_outreach_for_actor?(kind, actor_did, since, opts \\ [])
      when is_binary(kind) and is_binary(actor_did) and is_struct(since, DateTime) do
    query =
      from(event in InteractionEvent,
        where:
          event.actor_did == ^actor_did and event.state == "completed" and
            event.terminal_at >= ^since and
            fragment("json_extract(?, '$.action')", event.payload) == ^kind and
            fragment("json_extract(?, '$.cycle_status')", event.payload) in [
              "acted",
              "simulated"
            ]
      )

    query = exclude_event(query, Keyword.get(opts, :exclude_event_key))
    repo(opts).exists?(query)
  end

  def prune(opts \\ []) do
    repo = repo(opts)
    retention_days = Keyword.get(opts, :retention_days, @default_retention_days)
    event_limit = Keyword.get(opts, :event_limit, @default_event_limit)
    current_time = Keyword.get(opts, :now, now())
    cutoff = DateTime.add(current_time, -retention_days * 24 * 60 * 60, :second)

    {expired, _rows} =
      repo.delete_all(
        from(event in InteractionEvent,
          where: event.state in ^@terminal_states and event.terminal_at < ^cutoff
        )
      )

    overflow_keys =
      repo.all(
        from(event in InteractionEvent,
          where: event.state in ^@terminal_states,
          order_by: [desc: event.terminal_at, desc: event.event_key],
          select: event.event_key
        )
      )
      |> Enum.drop(max(event_limit, 0))

    {overflow, _rows} =
      repo.delete_all(from(event in InteractionEvent, where: event.event_key in ^overflow_keys))

    {:ok, %{expired: expired, overflow: overflow}}
  end

  defp exclude_event(query, event_key) when is_binary(event_key) and event_key != "",
    do: from(event in query, where: event.event_key != ^event_key)

  defp exclude_event(query, _event_key), do: query

  defp key_part(nil), do: ""
  defp key_part(value), do: to_string(value)

  defp fetch!(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> value
      _value -> raise ArgumentError, "#{key} must be a non-empty string"
    end
  end

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp parse_time(%DateTime{} = value), do: microsecond(value)

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> microsecond(time)
      _error -> now()
    end
  end

  defp parse_time(_value), do: now()

  defp microsecond(value) do
    value |> DateTime.to_unix(:microsecond) |> DateTime.from_unix!(:microsecond)
  end

  defp json_safe(nil), do: nil
  defp json_safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_safe(item)} end)
  end

  defp json_safe(value), do: inspect(value)

  defp repo(opts), do: Keyword.get(opts, :repo, Repo)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
