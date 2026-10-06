defmodule JidoDelvetown.Inspection do
  @moduledoc "Read-only, bounded inspection of local AgentJido memory and effect health."

  import Ecto.Query

  alias JidoDelvetown.{AuditLog, Automation, Repo}

  alias JidoDelvetown.Storage.{
    Actor,
    Conversation,
    Effect,
    ImageArtifact,
    ImageDraft,
    InteractionEvent,
    LegacyImport,
    ScanState
  }

  @event_states ["pending", "claimed", "completed", "ignored", "failed"]
  @effect_states ["reserved", "uncertain", "completed", "permanent_failure"]
  @simulated_post_actions ["post", "reply", "welcome"]
  @like_proposal_scan_limit 100
  @default_limit 8

  def snapshot(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    limit = opts |> Keyword.get(:limit, @default_limit) |> max(0)
    simulated_limit = opts |> Keyword.get(:simulated_limit, 25) |> max(0)
    image_limit = opts |> Keyword.get(:image_limit, 12) |> max(0)

    %{
      events: %{counts: grouped_counts(repo, InteractionEvent, :state, @event_states)},
      simulated_posts: simulated_posts(repo, simulated_limit),
      like_proposals: like_proposals(repo, simulated_limit),
      image_drafts: image_drafts(repo, image_limit),
      actors: %{recent: recent_actors(repo, limit)},
      conversations: %{
        counts: grouped_counts(repo, Conversation, :status, ["active", "closed"]),
        recent: recent_conversations(repo, limit)
      },
      scans: scan_watermarks(repo),
      effects: effect_health(repo, limit),
      automation: %{
        proactive_review: Automation.proactive_review_health(repo: repo)
      },
      sqlite: %{
        migrations: migration_status(repo),
        legacy_imports: legacy_import_status(repo)
      }
    }
  end

  defp image_drafts(repo, limit) do
    repo.all(
      from(draft in ImageDraft,
        join: artifact in ImageArtifact,
        on: artifact.digest == draft.artifact_digest,
        order_by: [desc: draft.updated_at, asc: draft.draft_key],
        limit: ^limit,
        select: {draft, artifact}
      )
    )
    |> Enum.map(&image_draft_summary/1)
  end

  defp image_draft_summary({draft, artifact}) do
    %{
      draft_key: draft.draft_key,
      caption: draft.caption,
      alt_text: draft.alt_text,
      validation_state: "valid",
      publication_state: draft.state,
      publication_failure_present?: not is_nil(draft.failure),
      post_uri: map_value(draft.post_receipt, "uri"),
      published_at: iso8601(draft.published_at),
      inserted_at: iso8601(draft.inserted_at),
      artifact: %{
        digest: artifact.digest,
        preview_data_url: preview_data_url(artifact),
        mime_type: artifact.mime_type,
        byte_size: artifact.byte_size,
        width: artifact.width,
        height: artifact.height,
        upload_state: artifact.state,
        upload_attempt_count: artifact.upload_attempt_count,
        upload_failure_present?: not is_nil(artifact.failure),
        uploaded_at: iso8601(artifact.uploaded_at),
        source: map_value(artifact.source_metadata, "source"),
        filename: map_value(artifact.source_metadata, "filename")
      }
    }
  end

  defp preview_data_url(%{mime_type: mime_type, bytes: bytes})
       when is_binary(mime_type) and is_binary(bytes) do
    "data:#{mime_type};base64,#{Base.encode64(bytes)}"
  end

  defp preview_data_url(_artifact), do: nil

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

  defp like_proposals(_repo, 0), do: []

  defp like_proposals(repo, limit) do
    scan_limit = min(max(limit * 4, limit), @like_proposal_scan_limit)

    repo.all(
      from(event in InteractionEvent,
        left_join: actor in Actor,
        on: actor.did == event.actor_did,
        where: fragment("json_extract(?, '$.action')", event.payload) == "like",
        order_by: [
          desc: fragment("json_extract(?, '$.like_review.selected_at')", event.payload),
          desc: event.updated_at,
          desc: event.occurred_at,
          asc: event.event_key
        ],
        limit: ^scan_limit,
        select: %{
          event_key: event.event_key,
          event_state: event.state,
          cycle_status: fragment("json_extract(?, '$.cycle_status')", event.payload),
          target_uri: event.record_uri,
          target_author_did: event.actor_did,
          target_author_handle:
            fragment("json_extract(?, '$.like_review.author.handle')", event.payload),
          target_author_display_name:
            fragment("json_extract(?, '$.like_review.author.display_name')", event.payload),
          remembered_handle: actor.handle,
          remembered_display_name: actor.display_name,
          post_text: fragment("json_extract(?, '$.like_review.post_text')", event.payload),
          selection_reason: fragment("json_extract(?, '$.selection.reason')", event.payload),
          policy_score: fragment("json_extract(?, '$.selection.score')", event.payload),
          selected_at: fragment("json_extract(?, '$.like_review.selected_at')", event.payload),
          budget_date: fragment("json_extract(?, '$.like_review.budget.date')", event.payload),
          budget_likes: fragment("json_extract(?, '$.like_review.budget.likes')", event.payload),
          budget_limit: fragment("json_extract(?, '$.like_review.budget.limit')", event.payload),
          budget_remaining:
            fragment("json_extract(?, '$.like_review.budget.remaining')", event.payload),
          published_status:
            fragment("json_extract(?, '$.manual_publication.status')", event.payload),
          published_at:
            fragment("json_extract(?, '$.manual_publication.published_at')", event.payload),
          published_uri: fragment("json_extract(?, '$.manual_publication.uri')", event.payload),
          publication_effect_key:
            fragment("json_extract(?, '$.manual_publication.effect_key')", event.payload),
          occurred_at: event.occurred_at,
          terminal_at: event.terminal_at
        }
      )
    )
    |> Enum.map(&like_proposal_summary/1)
    |> Enum.uniq_by(&(&1.target_uri || &1.event_key))
    |> Enum.take(limit)
  end

  defp like_proposal_summary(row) do
    %{
      event_key: row.event_key,
      event_state: row.event_state,
      proposal_status: row.cycle_status,
      publication_state: like_publication_state(row),
      target_uri: row.target_uri,
      target_author: %{
        did: row.target_author_did,
        handle: row.target_author_handle || row.remembered_handle,
        display_name: row.target_author_display_name || row.remembered_display_name
      },
      post_text: row.post_text,
      selection_reason: row.selection_reason,
      policy_score: row.policy_score,
      selected_at: row.selected_at || iso8601(row.terminal_at) || iso8601(row.occurred_at),
      published_at: row.published_at,
      published_uri: row.published_uri,
      publication_effect_key: row.publication_effect_key,
      budget: %{
        date: row.budget_date,
        likes: row.budget_likes,
        limit: row.budget_limit,
        remaining: row.budget_remaining
      }
    }
  end

  defp like_publication_state(%{event_state: "failed"}), do: "failed"
  defp like_publication_state(%{event_state: "ignored"}), do: "ignored"
  defp like_publication_state(%{published_status: "completed"}), do: "published"

  defp like_publication_state(%{published_status: status})
       when is_binary(status) and status != "",
       do: status

  defp like_publication_state(%{cycle_status: "acted"}), do: "published"

  defp like_publication_state(%{cycle_status: status}) when status in ["proposed", "simulated"],
    do: status

  defp like_publication_state(row), do: row.cycle_status || row.event_state

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

    %{
      counts: counts,
      reconciled: AuditLog.reconciled_effect_count(repo: repo),
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

  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
  defp map_value(_map, _key), do: nil
end
