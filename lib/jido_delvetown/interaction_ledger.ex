defmodule JidoDelvetown.InteractionLedger do
  @moduledoc "Durable interaction, actor, and conversation memory."

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{Actor, Conversation, InteractionEvent}

  @terminal_states ["completed", "ignored", "failed"]
  @default_retention_days 90
  @default_event_limit 5_000

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

    repo.insert_all(
      InteractionEvent,
      [row],
      on_conflict:
        {:replace,
         [:kind, :actor_did, :record_uri, :source_id, :occurred_at, :payload, :updated_at]},
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

  def record_cycle(%{candidate: nil}, _decision, _completed_at), do: :ok
  def record_cycle(%{defer?: true}, _decision, _completed_at), do: :ok

  def record_cycle(cycle, decision, completed_at) do
    candidate = cycle.candidate
    event_key = candidate_event_key(cycle.kind, candidate.id)
    actor_did = get_in(candidate, [:author, :did])

    attrs = %{
      event_key: event_key,
      kind: Map.get(candidate, :reason, cycle.kind),
      actor_did: actor_did,
      record_uri: Map.get(candidate, :uri),
      source_id: candidate.id,
      occurred_at: Map.get(candidate, :indexed_at) || completed_at,
      payload: %{
        cycle_kind: cycle.kind,
        mode: cycle.mode,
        intent: cycle.intent,
        action: decision.action,
        cycle_status: cycle.status
      }
    }

    with {:ok, _event} <- observe(attrs),
         {:ok, _claimed} <- claim(event_key),
         {:ok, _finished} <- finish(event_key, cycle_outcome(cycle.status), cycle_failure(cycle)),
         :ok <- remember_actor(candidate, cycle, completed_at),
         :ok <- remember_conversation(candidate, cycle, decision, completed_at) do
      :ok
    else
      {:error, {:not_claimable, state}} when state in @terminal_states -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def actor(did, opts \\ []), do: repo(opts).get(Actor, did)
  def conversation(root_uri, opts \\ []), do: repo(opts).get(Conversation, root_uri)
  def event(event_key, opts \\ []), do: repo(opts).get(InteractionEvent, event_key)

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

  defp remember_actor(%{author: %{did: did} = author}, cycle, at) when is_binary(did) do
    repo = Repo
    seen_at = parse_time(at)
    contacted? = cycle.status == "acted"

    repo.transaction(
      fn ->
        case repo.get(Actor, did) do
          nil ->
            %Actor{
              did: did,
              handle: Map.get(author, :handle),
              display_name: Map.get(author, :display_name),
              profile: json_safe(author),
              first_seen_at: seen_at,
              last_seen_at: seen_at,
              last_interaction_at: if(contacted?, do: seen_at),
              contact_count: if(contacted?, do: 1, else: 0),
              metadata: %{}
            }
            |> repo.insert!()

          actor ->
            actor
            |> Ecto.Changeset.change(
              handle: Map.get(author, :handle) || actor.handle,
              display_name: Map.get(author, :display_name) || actor.display_name,
              profile: Map.merge(actor.profile || %{}, json_safe(author)),
              last_seen_at: seen_at,
              last_interaction_at: if(contacted?, do: seen_at, else: actor.last_interaction_at),
              contact_count: actor.contact_count + if(contacted?, do: 1, else: 0)
            )
            |> repo.update!()
        end
      end,
      mode: :immediate
    )
    |> transaction_ok()
  end

  defp remember_actor(_candidate, _cycle, _at), do: :ok

  defp remember_conversation(candidate, %{status: "acted"}, %{action: "reply"}, at) do
    root_uri = get_in(candidate, [:root, :uri])

    if is_binary(root_uri) do
      repo = Repo
      action_at = parse_time(at)

      repo.transaction(
        fn ->
          case repo.get(Conversation, root_uri) do
            nil ->
              %Conversation{
                root_uri: root_uri,
                actor_did: get_in(candidate, [:author, :did]),
                turn_count: 1,
                last_record_uri: Map.get(candidate, :uri),
                last_action: "reply",
                last_action_at: action_at,
                status: "active",
                metadata: %{}
              }
              |> repo.insert!()

            conversation ->
              conversation
              |> Ecto.Changeset.change(
                actor_did: get_in(candidate, [:author, :did]) || conversation.actor_did,
                turn_count: conversation.turn_count + 1,
                last_record_uri: Map.get(candidate, :uri),
                last_action: "reply",
                last_action_at: action_at,
                status: "active"
              )
              |> repo.update!()
          end
        end,
        mode: :immediate
      )
      |> transaction_ok()
    else
      :ok
    end
  end

  defp remember_conversation(_candidate, _cycle, _decision, _at), do: :ok

  defp transaction_ok({:ok, _value}), do: :ok
  defp transaction_ok({:error, reason}), do: {:error, reason}

  defp cycle_outcome("failed"), do: :failed
  defp cycle_outcome(status) when status in ["ignored", "skipped"], do: :ignored
  defp cycle_outcome(_status), do: :completed

  defp cycle_failure(%{errors: errors}) when errors != [], do: %{errors: errors}
  defp cycle_failure(_cycle), do: %{}

  defp candidate_event_key(kind, id) do
    digest = :crypto.hash(:sha256, [kind, <<0>>, id]) |> Base.url_encode64(padding: false)
    "candidate:" <> digest
  end

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
