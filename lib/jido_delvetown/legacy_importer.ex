defmodule JidoDelvetown.LegacyImporter do
  @moduledoc "Imports the former DETS store and Jido file checkpoint into SQLite."

  import Ecto.Query

  alias JidoDelvetown.Config
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{AuditEvent, Effect, InteractionEvent, LegacyImport, ScanState}

  @import_name "dets-and-file-v1"
  @dets_table JidoDelvetown.LegacyImporter.Dets
  @namespace "jido/delvetown"
  @agent_id "delvetown-agent"

  def preview(opts \\ []) do
    with {:ok, dets} <- read_dets(options(opts)),
         {:ok, checkpoint} <- read_checkpoint(options(opts)) do
      {:ok, summary(dets, checkpoint, options(opts))}
    end
  end

  def run(opts \\ []) do
    opts = options(opts)

    with {:ok, dets} <- read_dets(opts),
         {:ok, checkpoint} <- read_checkpoint(opts) do
      import_transaction(dets, checkpoint, opts)
    end
  end

  defp import_transaction(dets, checkpoint, opts) do
    checksum = checksum(dets.source_bytes, checkpoint)

    opts.repo.transaction(
      fn ->
        case opts.repo.get(LegacyImport, @import_name) do
          %LegacyImport{status: "complete", checksum: ^checksum} = import ->
            {:reused, import.details}

          _missing_or_changed ->
            details = dets |> import_all(checkpoint, opts) |> json_safe()
            record_import(checksum, details, opts)
            {:imported, details}
        end
      end,
      mode: :immediate
    )
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:sqlite_import_failed, reason}}
    end
  rescue
    exception -> {:error, {:sqlite_import_failed, Exception.message(exception)}}
  end

  def verify(opts \\ []) do
    opts = options(opts)

    with {:ok, preview} <- preview(opts),
         %LegacyImport{status: "complete", details: details} <-
           opts.repo.get(LegacyImport, @import_name),
         :ok <- verify_counts(preview, details, opts),
         :ok <- verify_checkpoint(preview, opts) do
      {:ok, %{status: :verified, details: details}}
    else
      nil -> {:error, :legacy_import_not_complete}
      {:error, _reason} = error -> error
      _other -> {:error, :legacy_import_not_complete}
    end
  end

  defp options(%{repo: _repo} = opts), do: opts

  defp options(opts) do
    %{
      repo: Keyword.get(opts, :repo, Repo),
      dets_path: Keyword.get(opts, :dets_path, Config.legacy_state_path()),
      checkpoint_path: Keyword.get(opts, :checkpoint_path, Config.checkpoint_path()),
      namespace: Keyword.get(opts, :namespace, @namespace),
      agent_id: Keyword.get(opts, :agent_id, @agent_id)
    }
  end

  defp read_dets(%{dets_path: path}) do
    if File.regular?(path) do
      case :dets.open_file(@dets_table,
             file: String.to_charlist(path),
             type: :set,
             access: :read
           ) do
        {:ok, @dets_table} ->
          try do
            entries = :dets.foldl(&[&1 | &2], [], @dets_table)
            {:ok, %{entries: entries, source_bytes: File.read!(path)}}
          after
            :dets.close(@dets_table)
          end

        {:error, reason} ->
          {:error, {:legacy_dets_open_failed, reason}}
      end
    else
      {:ok, %{entries: [], source_bytes: <<>>}}
    end
  end

  defp read_checkpoint(opts) do
    key = checkpoint_key(opts)

    case Jido.Persistence.File.get(key, path: opts.checkpoint_path) do
      {:ok, bytes} -> {:ok, %{key: key, bytes: bytes}}
      {:error, :not_found} -> {:ok, nil}
      {:error, reason} -> {:error, {:legacy_checkpoint_read_failed, reason}}
    end
  end

  defp checkpoint_key(opts) do
    ref =
      Jido.Agent.Ref.new!(
        namespace: opts.namespace,
        partition: nil,
        id: opts.agent_id
      )

    Jido.Persistence.agent_key(ref)
  end

  defp import_all(dets, checkpoint, opts) do
    counts =
      Enum.reduce(dets.entries, empty_counts(), fn entry, counts ->
        import_entry(entry, counts, opts)
      end)

    checkpoint_count = import_checkpoint(checkpoint, opts)
    Map.put(counts, :checkpoints, checkpoint_count)
  end

  defp import_entry({:cursor, cursor}, counts, opts) when is_binary(cursor) do
    now = now()

    opts.repo.insert_all(
      ScanState,
      [
        %{
          name: "notifications",
          cursor: cursor,
          metadata: %{"source" => "legacy_dets"},
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:cursor, :metadata, :updated_at]},
      conflict_target: [:name]
    )

    increment(counts, :cursors)
  end

  defp import_entry({{:seen, uri}, seen}, counts, opts) when is_binary(uri) do
    at = parse_time(map_value(seen, :seen_at))
    now = now()

    opts.repo.insert_all(
      InteractionEvent,
      [
        %{
          event_key: seen_event_key(uri),
          kind: "legacy_seen",
          record_uri: uri,
          occurred_at: at,
          state: "completed",
          attempt_count: 0,
          payload: %{"source" => "legacy_dets"},
          terminal_at: at,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:event_key]
    )

    increment(counts, :seen)
  end

  defp import_entry({{:effect, key}, effect}, counts, opts) when is_binary(key) do
    now = now()

    row = %{
      operation_key: key,
      kind: legacy_effect_kind(key),
      collection: map_value(effect, :collection),
      rkey: map_value(effect, :rkey),
      status: effect |> map_value(:status) |> to_string(),
      attempt_count: 0,
      receipt: json_safe(map_value(effect, :receipt)),
      reserved_at: parse_time(map_value(effect, :created_at)),
      completed_at: optional_time(map_value(effect, :completed_at)),
      inserted_at: now,
      updated_at: now
    }

    opts.repo.insert_all(
      Effect,
      [row],
      on_conflict:
        {:replace,
         [
           :kind,
           :collection,
           :rkey,
           :status,
           :receipt,
           :reserved_at,
           :completed_at,
           :updated_at
         ]},
      conflict_target: [:operation_key]
    )

    increment(counts, :effects)
  end

  defp import_entry({{:event, sequence}, event}, counts, opts) when is_integer(sequence) do
    now = now()

    opts.repo.insert_all(
      AuditEvent,
      [
        %{
          source_key: "legacy:dets:event:#{sequence}",
          type: event |> map_value(:type) |> to_string(),
          data:
            event
            |> map_value(:data)
            |> json_safe()
            |> Kernel.||(%{})
            |> Map.put("legacy_sequence", sequence),
          occurred_at: parse_time(map_value(event, :at)),
          inserted_at: now
        }
      ],
      on_conflict: {:replace, [:type, :data, :occurred_at, :inserted_at]},
      conflict_target: [:source_key]
    )

    increment(counts, :events)
  end

  defp import_entry(_entry, counts, _opts), do: increment(counts, :unknown)

  defp import_checkpoint(nil, _opts), do: 0

  defp import_checkpoint(%{key: key, bytes: bytes}, opts) do
    case Jido.Persistence.Ecto.put(key, bytes, repo: opts.repo) do
      :ok -> 1
      {:error, reason} -> opts.repo.rollback({:checkpoint_write_failed, reason})
    end
  end

  defp record_import(checksum, details, opts) do
    now = now()

    opts.repo.insert_all(
      LegacyImport,
      [
        %{
          name: @import_name,
          checksum: checksum,
          status: "complete",
          details: json_safe(details),
          imported_at: now,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:checksum, :status, :details, :imported_at, :updated_at]},
      conflict_target: [:name]
    )
  end

  defp verify_counts(preview, details, opts) do
    checks = [
      cursors: {preview.cursors, count_scan_cursor(opts.repo)},
      effects: {preview.effects, count_all(opts.repo, Effect)},
      seen: {preview.seen, count_interactions(opts.repo, "legacy_seen")},
      events: {preview.events, count_legacy_audit_events(opts.repo)}
    ]

    case Enum.find(checks, fn {_name, {expected, actual}} -> actual < expected end) do
      nil ->
        verify_recorded_counts(preview, details)

      {name, values} ->
        {:error, {:legacy_import_count_mismatch, name, values}}
    end
  end

  defp verify_checkpoint(%{checkpoints: 0}, _opts), do: :ok

  defp verify_checkpoint(%{checkpoint_key: key}, opts) do
    case Jido.Persistence.Ecto.get(key, repo: opts.repo) do
      {:ok, _bytes} -> :ok
      {:error, reason} -> {:error, {:checkpoint_verification_failed, reason}}
    end
  end

  defp verify_recorded_counts(preview, details) do
    fields = [:cursors, :seen, :effects, :events, :unknown, :checkpoints]

    case Enum.find(fields, fn field ->
           string_integer(details, Atom.to_string(field)) != Map.fetch!(preview, field)
         end) do
      nil -> :ok
      field -> {:error, {:legacy_import_record_mismatch, field}}
    end
  end

  defp count_scan_cursor(repo) do
    repo.one(from(state in ScanState, where: state.name == "notifications", select: count()))
  end

  defp count_all(repo, schema) do
    repo.one(from(item in schema, select: count()))
  end

  defp count_interactions(repo, kind) do
    repo.one(from(event in InteractionEvent, where: event.kind == ^kind, select: count()))
  end

  defp count_legacy_audit_events(repo) do
    repo.one(
      from(event in AuditEvent,
        where: like(event.source_key, "legacy:dets:event:%"),
        select: count()
      )
    )
  end

  defp summary(dets, checkpoint, _opts) do
    counts =
      Enum.reduce(dets.entries, empty_counts(), fn
        {:cursor, _cursor}, acc -> increment(acc, :cursors)
        {{:seen, _uri}, _seen}, acc -> increment(acc, :seen)
        {{:effect, _key}, _effect}, acc -> increment(acc, :effects)
        {{:event, _sequence}, _event}, acc -> increment(acc, :events)
        _entry, acc -> increment(acc, :unknown)
      end)

    counts
    |> Map.put(:checkpoints, if(checkpoint, do: 1, else: 0))
    |> Map.put(:checkpoint_key, checkpoint && checkpoint.key)
  end

  defp checksum(dets_bytes, checkpoint) do
    checkpoint_bytes = if checkpoint, do: checkpoint.bytes, else: <<>>

    :crypto.hash(:sha256, [dets_bytes, <<0>>, checkpoint_bytes])
    |> Base.url_encode64(padding: false)
  end

  defp empty_counts,
    do: %{cursors: 0, seen: 0, effects: 0, events: 0, unknown: 0, checkpoints: 0}

  defp increment(counts, name), do: Map.update!(counts, name, &(&1 + 1))

  defp seen_event_key(uri) do
    digest = :crypto.hash(:sha256, uri) |> Base.url_encode64(padding: false)
    "legacy:seen:" <> digest
  end

  defp legacy_effect_kind(key) do
    case String.split(key, ":", parts: 2) do
      [kind, _digest] -> kind
      _other -> "legacy"
    end
  end

  defp parse_time(value) do
    case optional_time(value) do
      %DateTime{} = time -> time
      nil -> now()
    end
  end

  defp optional_time(%DateTime{} = value), do: with_microsecond_precision(value)

  defp optional_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> with_microsecond_precision(time)
      _error -> nil
    end
  end

  defp optional_time(_value), do: nil

  defp map_value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp map_value(_map, _key), do: nil

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

  defp string_integer(map, key) do
    atom_key =
      case key do
        "cursors" -> :cursors
        "seen" -> :seen
        "effects" -> :effects
        "events" -> :events
        "unknown" -> :unknown
        "checkpoints" -> :checkpoints
      end

    Map.get(map, key) || Map.get(map, atom_key) || 0
  end

  defp with_microsecond_precision(%DateTime{} = value) do
    microseconds = DateTime.to_unix(value, :microsecond)
    DateTime.from_unix!(microseconds, :microsecond)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
