defmodule JidoDelvetown.Settings.LegacyEnvImporter do
  @moduledoc """
  Imports former runtime environment settings into SQLite one time.

  Only settings owned by the runtime settings database are eligible. Bootstrap
  paths, one-time setup inputs, and external secrets remain outside this import.
  A completed import marker is final, even when the process environment changes.
  """

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings
  alias JidoDelvetown.Settings.{Bootstrap, Contract}
  alias JidoDelvetown.Storage.{AuditEvent, LegacyImport, SettingsRevision}

  @import_name "legacy-environment-v1"
  @revision_source "legacy_environment"
  @redacted "[REDACTED]"

  @doc "Returns a safe preview of eligible legacy environment values."
  @spec preview(keyword()) :: {:ok, map()} | {:error, term()}
  def preview(opts \\ []) do
    opts = options(opts)

    with {:ok, prepared} <- prepare(opts) do
      {:ok, preview_summary(prepared, opts)}
    end
  end

  @doc "Imports eligible legacy environment values at most once."
  @spec run(keyword()) :: {:ok, {atom(), map()}} | {:error, term()}
  def run(opts \\ []) do
    opts = options(opts)

    case completed_import(opts) do
      %LegacyImport{} = legacy_import ->
        {:ok, {:reused, legacy_import.details}}

      nil ->
        recover_or_import(opts)
    end
  end

  defp recover_or_import(opts) do
    case imported_revision(opts) do
      %SettingsRevision{} = revision ->
        details = recovered_details(revision, opts)
        complete(:imported, details, revision.metadata["checksum"], opts)

      nil ->
        with {:ok, prepared} <- prepare(opts),
             {:ok, current} <- Settings.current(repo: opts.repo, scope: opts.scope) do
          import_prepared(prepared, current, opts)
        end
    end
  end

  defp import_prepared(%{changes: changes} = prepared, current, opts)
       when map_size(changes) == 0 do
    details = details("no_values", prepared, current, opts)
    complete(:imported, details, prepared.checksum, opts)
  end

  defp import_prepared(prepared, %{version: 1, values: values} = current, opts) do
    if values == Contract.defaults() do
      apply_changes(prepared, current, opts)
    else
      skip_existing(prepared, current, opts)
    end
  end

  defp import_prepared(prepared, current, opts), do: skip_existing(prepared, current, opts)

  defp apply_changes(prepared, current, opts) do
    metadata = %{
      "legacy_import_name" => opts.import_name,
      "checksum" => prepared.checksum,
      "setting_keys" => prepared.keys,
      "environment_names" => prepared.environment_names
    }

    update_opts = [
      repo: opts.repo,
      scope: opts.scope,
      expected_version: current.version,
      source: @revision_source,
      metadata: metadata,
      confirmed: confirmations(prepared.changes)
    ]

    case Settings.update(prepared.changes, update_opts) do
      {:ok, updated} ->
        details = details("imported", prepared, updated, opts)
        complete(:imported, details, prepared.checksum, opts)

      {:error, {:stale_settings, _expected, _actual}} ->
        run(opts_to_keyword(opts))

      {:error, reason} ->
        {:error, {:legacy_environment_import_failed, reason}}
    end
  end

  defp skip_existing(prepared, current, opts) do
    details = details("skipped_existing_settings", prepared, current, opts)
    complete(:skipped, details, prepared.checksum, opts)
  end

  defp complete(result, details, checksum, opts) do
    now = opts.now.()

    opts.repo.transaction(
      fn ->
        {inserted, _rows} =
          opts.repo.insert_all(
            LegacyImport,
            [
              %{
                name: opts.import_name,
                checksum: checksum || digest(details),
                status: "complete",
                details: details,
                imported_at: now,
                inserted_at: now,
                updated_at: now
              }
            ],
            on_conflict: :nothing,
            conflict_target: [:name]
          )

        if inserted == 1 do
          record_audit(details, now, opts)
          {result, details}
        else
          legacy_import = opts.repo.get!(LegacyImport, opts.import_name)
          {:reused, legacy_import.details}
        end
      end,
      mode: :immediate
    )
    |> case do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:legacy_environment_import_failed, reason}}
    end
  rescue
    exception -> {:error, {:legacy_environment_import_failed, Exception.message(exception)}}
  end

  defp record_audit(details, now, opts) do
    opts.repo.insert_all(
      AuditEvent,
      [
        %{
          source_key: "legacy:settings:#{opts.import_name}",
          type: "settings_import",
          data: details,
          occurred_at: now,
          inserted_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:source_key]
    )
  end

  defp prepare(opts) do
    eligible_definitions()
    |> Enum.reduce_while({:ok, %{}, []}, fn definition, {:ok, changes, entries} ->
      case Map.fetch(opts.environment, definition.legacy_env) do
        :error ->
          {:cont, {:ok, changes, entries}}

        {:ok, raw_value} ->
          with {:ok, value} <- parse(definition, raw_value),
               :ok <- Contract.validate(definition.key, value) do
            entry = %{
              definition: definition,
              environment: definition.legacy_env,
              value: value
            }

            {:cont, {:ok, Map.put(changes, definition.key, value), [entry | entries]}}
          else
            {:error, reason} ->
              {:halt,
               {:error,
                {:invalid_legacy_environment, definition.legacy_env, definition.key, reason}}}
          end
      end
    end)
    |> case do
      {:ok, changes, entries} ->
        entries = Enum.reverse(entries)

        {:ok,
         %{
           changes: changes,
           entries: entries,
           keys: Enum.map(entries, &Atom.to_string(&1.definition.key)),
           environment_names: Enum.map(entries, & &1.environment),
           ignored_external_secrets: ignored_external_secrets(opts.environment),
           checksum: import_checksum(entries)
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp eligible_definitions do
    Contract.database_definitions()
    |> Enum.reject(&is_nil(&1.legacy_env))
  end

  defp ignored_external_secrets(environment) do
    Contract.external_definitions()
    |> Enum.filter(&(&1.storage == :external_secret and not is_nil(&1.legacy_env)))
    |> Enum.filter(&Map.has_key?(environment, &1.legacy_env))
    |> Enum.map(& &1.legacy_env)
  end

  defp parse(%{key: :autonomy_mode}, raw_value) do
    case parse_boolean(raw_value) do
      {:ok, true} -> {:ok, "autonomous"}
      {:ok, false} -> {:ok, "observe"}
      {:error, _reason} = error -> error
    end
  end

  defp parse(%{type: :boolean}, raw_value), do: parse_boolean(raw_value)

  defp parse(%{type: :integer}, raw_value) when is_binary(raw_value) do
    case Integer.parse(String.trim(raw_value)) do
      {value, ""} -> {:ok, value}
      _invalid -> {:error, :expected_integer}
    end
  end

  defp parse(%{type: :integer}, raw_value) when is_integer(raw_value), do: {:ok, raw_value}
  defp parse(%{type: :string}, raw_value) when is_binary(raw_value), do: {:ok, raw_value}
  defp parse(%{type: :enum}, raw_value) when is_binary(raw_value), do: {:ok, raw_value}
  defp parse(%{type: :cron}, raw_value) when is_binary(raw_value), do: {:ok, raw_value}
  defp parse(_definition, _raw_value), do: {:error, :unsupported_value}

  defp parse_boolean(value) when is_boolean(value), do: {:ok, value}

  defp parse_boolean(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      value when value in ~w(1 true yes on) -> {:ok, true}
      value when value in ~w(0 false no off) -> {:ok, false}
      _invalid -> {:error, :expected_boolean}
    end
  end

  defp parse_boolean(_value), do: {:error, :expected_boolean}

  defp confirmations(changes) do
    for {key, value} <- changes,
        {:ok, definition} = Contract.definition(key),
        {:confirm_value, ^value} <- [definition.safety.change_policy],
        do: key
  end

  defp preview_summary(prepared, opts) do
    %{
      import_name: opts.import_name,
      status: if(prepared.entries == [], do: :no_values, else: :ready),
      count: length(prepared.entries),
      settings: Enum.map(prepared.entries, &preview_entry/1),
      ignored_external_secrets: prepared.ignored_external_secrets
    }
  end

  defp preview_entry(entry) do
    %{
      key: entry.definition.key,
      environment: entry.environment,
      value: preview_value(entry.definition, entry.value)
    }
  end

  defp preview_value(%{safety: %{log_policy: :redact}}, nil), do: nil
  defp preview_value(%{safety: %{log_policy: :redact}}, _value), do: @redacted
  defp preview_value(_definition, value), do: value

  defp details(status, prepared, settings, opts) do
    %{
      "status" => status,
      "settings_scope" => opts.scope,
      "settings_schema_version" => settings.schema_version,
      "settings_version" => settings.version,
      "count" => length(prepared.entries),
      "setting_keys" => prepared.keys,
      "environment_names" => prepared.environment_names,
      "ignored_external_secrets" => prepared.ignored_external_secrets
    }
  end

  defp recovered_details(revision, opts) do
    metadata = revision.metadata || %{}

    %{
      "status" => "imported",
      "settings_scope" => opts.scope,
      "settings_schema_version" => revision.schema_version,
      "settings_version" => revision.version,
      "count" => length(metadata["setting_keys"] || []),
      "setting_keys" => metadata["setting_keys"] || [],
      "environment_names" => metadata["environment_names"] || [],
      "ignored_external_secrets" => [],
      "recovered" => true
    }
  end

  defp completed_import(opts) do
    case opts.repo.get(LegacyImport, opts.import_name) do
      %LegacyImport{status: "complete"} = legacy_import -> legacy_import
      _missing_or_incomplete -> nil
    end
  end

  defp imported_revision(opts) do
    opts.repo.all(
      from(revision in SettingsRevision,
        where: revision.settings_scope == ^opts.scope and revision.source == ^@revision_source,
        order_by: [desc: revision.version]
      )
    )
    |> Enum.find(&(&1.metadata["legacy_import_name"] == opts.import_name))
  end

  defp import_checksum(entries) do
    entries
    |> Enum.map(fn entry ->
      [
        Atom.to_string(entry.definition.key),
        preview_value(entry.definition, entry.value)
      ]
    end)
    |> digest()
  end

  defp digest(value) do
    value
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp options(opts) when is_list(opts) do
    %{
      repo: Keyword.get(opts, :repo, Repo),
      scope: Keyword.get(opts, :scope, Bootstrap.active_scope()),
      import_name: Keyword.get(opts, :import_name, @import_name),
      environment: opts |> Keyword.get_lazy(:env, &System.get_env/0) |> normalize_environment(),
      now: Keyword.get(opts, :now, &utc_now/0)
    }
  end

  defp normalize_environment(environment) when is_map(environment), do: environment
  defp normalize_environment(environment) when is_list(environment), do: Map.new(environment)

  defp opts_to_keyword(opts) do
    [
      repo: opts.repo,
      scope: opts.scope,
      import_name: opts.import_name,
      env: opts.environment,
      now: opts.now
    ]
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
