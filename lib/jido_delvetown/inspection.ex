defmodule JidoDelvetown.Inspection do
  @moduledoc "Read-only, bounded inspection of local AgentJido memory and effect health."

  import Ecto.Query

  alias JidoDelvetown.Repo

  alias JidoDelvetown.Storage.{
    Actor,
    AuditEvent,
    Conversation,
    Effect,
    InteractionEvent,
    LegacyImport,
    ScanState
  }

  @event_states ["pending", "claimed", "completed", "ignored", "failed"]
  @effect_states ["reserved", "uncertain", "completed", "permanent_failure"]
  @simulated_post_actions ["post", "reply", "welcome"]
  @default_limit 8

  def snapshot(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    limit = opts |> Keyword.get(:limit, @default_limit) |> max(0)
    simulated_limit = opts |> Keyword.get(:simulated_limit, 25) |> max(0)

    %{
      events: %{counts: grouped_counts(repo, InteractionEvent, :state, @event_states)},
      simulated_posts: simulated_posts(repo, simulated_limit),
      actors: %{recent: recent_actors(repo, limit)},
      conversations: %{
        counts: grouped_counts(repo, Conversation, :status, ["active", "closed"]),
        recent: recent_conversations(repo, limit)
      },
      scans: scan_watermarks(repo),
      effects: effect_health(repo, limit),
      sqlite: %{
        migrations: migration_status(repo),
        legacy_imports: legacy_import_status(repo)
      }
    }
  end

  defp grouped_counts(repo, schema, field_name, known_states) do
    observed =
      repo.all(
        from(row in schema,
          group_by: field(row, ^field_name),
          select: {field(row, ^field_name), count()}
        )
      )
      |> Map.new()

    Map.new(known_states, fn state -> {state, Map.get(observed, state, 0)} end)
  end

  defp recent_actors(repo, limit) do
    repo.all(
      from(actor in Actor,
        order_by: [desc: actor.last_interaction_at, desc: actor.last_seen_at, asc: actor.did],
        limit: ^limit,
        select: %{
          did: actor.did,
          handle: actor.handle,
          display_name: actor.display_name,
          last_seen_at: actor.last_seen_at,
          last_interaction_at: actor.last_interaction_at,
          contact_count: actor.contact_count,
          welcome_status: actor.welcome_status,
          opted_out?: actor.opted_out
        }
      )
    )
    |> Enum.map(&encode_times/1)
  end

  defp simulated_posts(repo, limit) do
    repo.all(
      from(event in InteractionEvent,
        where:
          event.state == "completed" and
            fragment("json_extract(?, '$.cycle_status')", event.payload) == "simulated" and
            fragment("json_extract(?, '$.action')", event.payload) in ^@simulated_post_actions,
        order_by: [desc: event.terminal_at, asc: event.event_key],
        limit: ^limit,
        select: %{
          event_key: event.event_key,
          action: fragment("json_extract(?, '$.action')", event.payload),
          text: fragment("json_extract(?, '$.text')", event.payload),
          topic: fragment("json_extract(?, '$.topic')", event.payload),
          reason: fragment("json_extract(?, '$.model_reason')", event.payload),
          response_format: fragment("json_extract(?, '$.response_format')", event.payload),
          intent: fragment("json_extract(?, '$.intent')", event.payload),
          published_status:
            fragment("json_extract(?, '$.manual_publication.status')", event.payload),
          published_at:
            fragment("json_extract(?, '$.manual_publication.published_at')", event.payload),
          published_uri: fragment("json_extract(?, '$.manual_publication.uri')", event.payload),
          actor_did: event.actor_did,
          record_uri: event.record_uri,
          simulated_at: event.terminal_at
        }
      )
    )
    |> Enum.map(&encode_times/1)
  end

  defp recent_conversations(repo, limit) do
    repo.all(
      from(conversation in Conversation,
        order_by: [desc: conversation.last_action_at, asc: conversation.root_uri],
        limit: ^limit,
        select: %{
          root_uri: conversation.root_uri,
          actor_did: conversation.actor_did,
          turn_count: conversation.turn_count,
          last_record_uri: conversation.last_record_uri,
          last_action: conversation.last_action,
          last_action_at: conversation.last_action_at,
          status: conversation.status
        }
      )
    )
    |> Enum.map(&encode_times/1)
  end

  defp scan_watermarks(repo) do
    repo.all(from(scan in ScanState, order_by: [asc: scan.name]))
    |> Enum.map(fn scan ->
      metadata = scan.metadata || %{}

      %{
        name: scan.name,
        cursor: scan.cursor,
        lease_active?: lease_active?(metadata["lease_until"]),
        last_completed_at: metadata["last_completed_at"],
        last_released_at: metadata["last_released_at"],
        updated_at: iso8601(scan.updated_at)
      }
    end)
  end

  defp effect_health(repo, limit) do
    counts = grouped_counts(repo, Effect, :status, @effect_states)

    attention =
      repo.all(
        from(effect in Effect,
          where: effect.status in ["reserved", "uncertain", "permanent_failure"],
          order_by: [desc: effect.updated_at, asc: effect.operation_key],
          limit: ^limit
        )
      )
      |> Enum.map(&effect_summary/1)

    receipts =
      repo.all(
        from(effect in Effect,
          where: effect.status == "completed",
          order_by: [desc: effect.completed_at, asc: effect.operation_key],
          limit: ^limit
        )
      )
      |> Enum.map(&effect_summary/1)

    reconciled =
      repo.aggregate(
        from(event in AuditEvent,
          where:
            event.type in ["create_record", "delete_record"] and
              fragment(
                "json_extract(?, '$.' || 'reconciled' || char(63)) = 1",
                event.data
              )
        ),
        :count,
        :id
      )

    %{
      counts: counts,
      reconciled: reconciled,
      attention: attention,
      completed_receipts: receipts
    }
  end

  defp effect_summary(effect) do
    receipt = effect.receipt || %{}

    %{
      operation_key: effect.operation_key,
      kind: effect.kind,
      collection: effect.collection,
      actor_did: effect.actor_did,
      rkey: effect.rkey,
      status: effect.status,
      attempt_count: effect.attempt_count,
      reserved_at: iso8601(effect.reserved_at),
      completed_at: iso8601(effect.completed_at),
      receipt: %{
        uri: receipt["uri"] || receipt[:uri],
        cid: receipt["cid"] || receipt[:cid]
      },
      failure_present?: not is_nil(effect.failure)
    }
  end

  defp migration_status(repo) do
    applied =
      repo.query!("SELECT version FROM schema_migrations ORDER BY version")
      |> Map.fetch!(:rows)
      |> List.flatten()
      |> Enum.map(&to_string/1)

    expected =
      :jido_delvetown
      |> Application.app_dir("priv/repo/migrations")
      |> Path.join("*.exs")
      |> Path.wildcard()
      |> Enum.map(&migration_version/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    pending = expected -- applied

    %{
      status: if(pending == [], do: "current", else: "pending"),
      applied: applied,
      pending: pending
    }
  end

  defp legacy_import_status(repo) do
    repo.all(from(import in LegacyImport, order_by: [asc: import.name]))
    |> Enum.map(fn import ->
      %{
        name: import.name,
        status: import.status,
        imported_at: iso8601(import.imported_at),
        counts: import_counts(import.details || %{})
      }
    end)
  end

  defp import_counts(details) do
    ~w(checkpoints cursors effects events seen unknown)
    |> Map.new(fn key -> {key, Map.get(details, key, 0)} end)
  end

  defp migration_version(path) do
    case Regex.run(~r/\A(\d+)_/, Path.basename(path), capture: :all_but_first) do
      [version] -> version
      _invalid -> nil
    end
  end

  defp lease_active?(lease_until) when is_binary(lease_until) do
    case DateTime.from_iso8601(lease_until) do
      {:ok, time, _offset} -> DateTime.compare(time, DateTime.utc_now()) == :gt
      _invalid -> false
    end
  end

  defp lease_active?(_lease_until), do: false

  defp encode_times(map) do
    Map.new(map, fn
      {key, %DateTime{} = value} -> {key, iso8601(value)}
      pair -> pair
    end)
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
