defmodule JidoDelvetown.Settings do
  @moduledoc """
  Reads and changes the active runtime settings.

  Each successful change updates the active row and adds one immutable revision
  in the same SQLite transaction. Callers can supply `:expected_version` to
  reject stale writes. Protected values also require their key in `:confirmed`.
  """

  import Ecto.Query, only: [from: 2]

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings.{Bootstrap, Contract, Schedules}
  alias JidoDelvetown.Settings.SecretStore
  alias JidoDelvetown.Storage.{Settings, SettingsRevision}

  @redacted "[REDACTED]"

  @type snapshot :: %{
          scope: String.t(),
          schema_version: pos_integer(),
          version: pos_integer(),
          values: %{required(atom()) => term()}
        }

  @type setting :: %{
          key: atom(),
          value: term(),
          schema_version: pos_integer(),
          version: pos_integer()
        }

  @type settings_reference :: %{
          scope: String.t(),
          schema_version: pos_integer(),
          version: pos_integer()
        }

  @spec current(keyword()) :: {:ok, snapshot()} | {:error, term()}
  def current(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    scope = Keyword.get(opts, :scope, Bootstrap.active_scope())

    with %Settings{} = settings <- repo.get(Settings, scope),
         {:ok, snapshot} <- snapshot(settings) do
      {:ok, snapshot}
    else
      nil -> {:error, {:settings_not_found, scope}}
      {:error, _reason} = error -> error
    end
  end

  @doc "Returns the stable identity of a settings snapshot."
  @spec reference(snapshot() | map() | keyword()) ::
          {:ok, settings_reference()} | {:error, term()}
  def reference(snapshot_or_opts \\ [])

  def reference(opts) when is_list(opts) do
    with {:ok, settings} <- current(opts) do
      reference(settings)
    end
  end

  def reference(settings) when is_map(settings) do
    scope = map_value(settings, :scope)
    schema_version = map_value(settings, :schema_version)
    version = map_value(settings, :version)

    if is_binary(scope) and scope != "" and is_integer(schema_version) and schema_version > 0 and
         is_integer(version) and version > 0 do
      {:ok, %{scope: scope, schema_version: schema_version, version: version}}
    else
      {:error, :invalid_settings_reference}
    end
  end

  def reference(_settings), do: {:error, :invalid_settings_reference}

  @spec fetch(atom() | String.t(), keyword()) :: {:ok, setting()} | {:error, term()}
  def fetch(key, opts \\ []) do
    with {:ok, definition} <- database_definition(key),
         {:ok, settings} <- current(opts) do
      {:ok,
       %{
         key: definition.key,
         value: Map.fetch!(settings.values, definition.key),
         schema_version: settings.schema_version,
         version: settings.version
       }}
    end
  end

  @doc "Returns one decrypted secret for internal runtime use."
  @spec fetch_secret(atom() | String.t(), keyword()) :: {:ok, setting()} | {:error, term()}
  def fetch_secret(key, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    scope = Keyword.get(opts, :scope, Bootstrap.active_scope())

    with {:ok, %{storage: :encrypted_database} = definition} <- Contract.definition(key),
         %Settings{} = settings <- repo.get(Settings, scope),
         :ok <- validate_schema_version(settings.schema_version),
         {:ok, values} <- decoded_values(settings.values),
         :ok <- validate_values(values) do
      {:ok,
       %{
         key: definition.key,
         value: Map.fetch!(values, definition.key),
         schema_version: settings.schema_version,
         version: settings.version
       }}
    else
      {:ok, definition} -> {:error, {:not_a_secret_setting, definition.key}}
      nil -> {:error, {:settings_not_found, scope}}
      {:error, _reason} = error -> error
    end
  end

  @doc "Lists recent immutable settings revisions, newest first."
  @spec revisions(keyword()) :: {:ok, [map()]} | {:error, term()}
  def revisions(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    scope = Keyword.get(opts, :scope, Bootstrap.active_scope())
    limit = Keyword.get(opts, :limit, 10)

    if is_integer(limit) and limit > 0 and limit <= 100 do
      revisions =
        repo.all(
          from(revision in SettingsRevision,
            where: revision.settings_scope == ^scope,
            order_by: [desc: revision.version],
            limit: ^limit
          )
        )

      {:ok, Enum.map(revisions, &revision_snapshot/1)}
    else
      {:error, :invalid_settings_revision_limit}
    end
  end

  @doc "Restores recorded settings from one revision and keeps encrypted secrets unchanged."
  @spec rollback(pos_integer(), keyword()) :: {:ok, snapshot()} | {:error, term()}
  def rollback(target_version, opts \\ [])

  def rollback(target_version, opts) when is_integer(target_version) and target_version > 0 do
    repo = Keyword.get(opts, :repo, Repo)
    scope = Keyword.get(opts, :scope, Bootstrap.active_scope())

    with {:ok, current} <- current(repo: repo, scope: scope),
         %SettingsRevision{} = revision <- revision(repo, scope, target_version),
         :ok <- validate_schema_version(revision.schema_version),
         {:ok, changes} <- rollback_changes(revision.values, current.values),
         {:ok, metadata} <- rollback_metadata(opts, target_version) do
      update_opts =
        opts
        |> Keyword.put(:repo, repo)
        |> Keyword.put(:scope, scope)
        |> Keyword.put_new(:expected_version, current.version)
        |> Keyword.put_new(:source, "runtime_rollback")
        |> Keyword.put(:metadata, metadata)

      update(changes, update_opts)
    else
      nil -> {:error, {:settings_revision_not_found, target_version}}
      {:error, _reason} = error -> error
    end
  end

  def rollback(_target_version, _opts), do: {:error, :invalid_settings_revision}

  @spec update(map() | keyword(), keyword()) :: {:ok, snapshot()} | {:error, term()}
  def update(changes, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    scope = Keyword.get(opts, :scope, Bootstrap.active_scope())

    with {:ok, changes} <- normalize_changes(changes),
         {:ok, update_opts} <- normalize_update_opts(opts) do
      repo
      |> transaction(scope, changes, update_opts)
      |> maybe_reconcile_schedules(repo, scope, changes)
    end
  end

  defp transaction(repo, scope, changes, update_opts) do
    repo.transaction(
      fn -> update_transaction(repo, scope, changes, update_opts) end,
      mode: :immediate
    )
  end

  defp maybe_reconcile_schedules({:ok, snapshot} = result, repo, scope, changes) do
    active_scope? = repo == Repo and scope == Bootstrap.active_scope()
    schedule_supplied? = Enum.any?(Map.keys(changes), &(&1 in Schedules.keys()))

    if active_scope? and schedule_supplied? do
      case reconcile_schedules() do
        :ok -> result
        {:error, reason} -> {:error, {:settings_activation_failed, :worker_reconcile, reason}}
      end
    else
      {:ok, snapshot}
    end
  end

  defp maybe_reconcile_schedules({:error, _reason} = error, _repo, _scope, _changes),
    do: error

  defp reconcile_schedules do
    module =
      Application.get_env(
        :jido_delvetown,
        :settings_schedule_reconciler,
        Module.concat(["JidoDelvetown", "Automation"])
      )

    apply(module, :reconcile_schedules, [])
  end

  defp update_transaction(repo, scope, changes, opts) do
    with %Settings{} = settings <- repo.get(Settings, scope),
         :ok <- validate_schema_version(settings.schema_version),
         :ok <- validate_expected_version(settings.version, opts.expected_version),
         {:ok, current_values} <- decoded_values(settings.values),
         next_values = Map.merge(current_values, changes),
         :ok <- validate_values(next_values),
         changed_keys <- changed_keys(current_values, next_values),
         :ok <- validate_confirmations(changed_keys, next_values, opts.confirmed) do
      persist_update(repo, settings, next_values, changed_keys, opts)
    else
      nil -> repo.rollback({:settings_not_found, scope})
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp persist_update(_repo, settings, values, [], _opts),
    do: public_snapshot(settings, values)

  defp persist_update(repo, settings, values, changed_keys, opts) do
    with {:ok, serialized} <- serialize(values, settings.values, changed_keys),
         {:ok, updated} <-
           settings
           |> Settings.changeset(%{values: serialized})
           |> repo.update(),
         {:ok, _revision} <- insert_revision(repo, updated, opts) do
      public_snapshot(updated, values)
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        repo.rollback({:settings_write_failed, changeset})

      {:error, reason} ->
        repo.rollback(reason)
    end
  end

  defp insert_revision(repo, settings, opts) do
    %SettingsRevision{}
    |> SettingsRevision.insert_changeset(%{
      settings_scope: settings.scope,
      version: settings.version,
      schema_version: settings.schema_version,
      values: revision_values(settings.values),
      source: opts.source,
      metadata: opts.metadata
    })
    |> repo.insert()
  end

  defp normalize_changes(changes) when is_map(changes) or is_list(changes) do
    if is_map(changes) or change_entries?(changes) do
      Enum.reduce_while(changes, {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
        with {:ok, definition} <- database_definition(key),
             :ok <- Contract.validate(definition.key, value),
             :ok <- ensure_unique_key(normalized, definition.key) do
          {:cont, {:ok, Map.put(normalized, definition.key, value)}}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    else
      {:error, :invalid_settings_changes}
    end
  end

  defp normalize_changes(_changes), do: {:error, :invalid_settings_changes}

  defp change_entries?(changes) do
    Enum.all?(changes, fn
      {key, _value} when is_atom(key) or is_binary(key) -> true
      _entry -> false
    end)
  end

  defp database_definition(key) do
    with {:ok, definition} <- Contract.definition(key),
         true <- definition.storage in [:database, :encrypted_database] do
      {:ok, definition}
    else
      false -> {:error, {:setting_not_persisted, key}}
      {:error, _reason} = error -> error
    end
  end

  defp map_value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp ensure_unique_key(normalized, key) do
    if Map.has_key?(normalized, key),
      do: {:error, {:duplicate_setting, key}},
      else: :ok
  end

  defp normalize_update_opts(opts) do
    source = Keyword.get(opts, :source, "runtime")
    metadata = Keyword.get(opts, :metadata, %{})
    expected_version = Keyword.get(opts, :expected_version)
    confirmed = Keyword.get(opts, :confirmed, [])

    cond do
      not is_binary(source) or not String.valid?(source) or String.trim(source) == "" or
          byte_size(source) > 255 ->
        {:error, :invalid_settings_source}

      not is_map(metadata) ->
        {:error, :invalid_settings_metadata}

      not is_nil(expected_version) and
          (not is_integer(expected_version) or expected_version < 1) ->
        {:error, :invalid_expected_settings_version}

      not is_list(confirmed) ->
        {:error, :invalid_settings_confirmations}

      true ->
        with {:ok, metadata} <- normalize_metadata(metadata) do
          normalize_confirmations(confirmed, source, metadata, expected_version)
        end
    end
  end

  defp normalize_metadata(metadata) do
    with {:ok, encoded} <- Jason.encode(metadata),
         {:ok, normalized} <- Jason.decode(encoded) do
      {:ok, normalized}
    else
      _error -> {:error, :invalid_settings_metadata}
    end
  end

  defp normalize_confirmations(confirmed, source, metadata, expected_version) do
    Enum.reduce_while(confirmed, {:ok, MapSet.new()}, fn key, {:ok, keys} ->
      case database_definition(key) do
        {:ok, definition} -> {:cont, {:ok, MapSet.put(keys, definition.key)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, keys} ->
        {:ok,
         %{
           source: source,
           metadata: metadata,
           expected_version: expected_version,
           confirmed: keys
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_schema_version(version) do
    current = Contract.schema_version()

    cond do
      version == current -> :ok
      version < current -> {:error, {:settings_schema_upgrade_required, version, current}}
      true -> {:error, {:unsupported_settings_schema, version, current}}
    end
  end

  defp validate_expected_version(_actual, nil), do: :ok
  defp validate_expected_version(version, version), do: :ok

  defp validate_expected_version(actual, expected),
    do: {:error, {:stale_settings, expected, actual}}

  defp validate_values(values) do
    with :ok <- validate_keys(values),
         :ok <- validate_each_value(values),
         :ok <- validate_combinations(values) do
      :ok
    end
  end

  defp validate_keys(values) do
    expected = MapSet.new(Contract.database_definitions(), & &1.key)
    actual = MapSet.new(Map.keys(values))
    missing = MapSet.difference(expected, actual) |> Enum.sort()
    unknown = MapSet.difference(actual, expected) |> Enum.sort()

    cond do
      missing != [] ->
        {:error, {:missing_settings, missing}}

      unknown != [] ->
        {:error, {:unknown_stored_settings, unknown}}

      true ->
        :ok
    end
  end

  defp validate_each_value(values) do
    Enum.reduce_while(Contract.database_definitions(), :ok, fn definition, :ok ->
      case Contract.validate(definition.key, Map.fetch!(values, definition.key)) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_combinations(values) do
    if values.conversation_non_response_limit <= values.conversation_turn_limit do
      :ok
    else
      {:error,
       {:invalid_settings_combination, :conversation_non_response_limit_exceeds_turn_limit}}
    end
  end

  defp validate_confirmations(changed_keys, values, confirmed) do
    Enum.reduce_while(changed_keys, :ok, fn key, :ok ->
      {:ok, definition} = Contract.definition(key)
      policy = definition.safety.change_policy

      case policy do
        {:confirm_value, protected_value} ->
          if Map.fetch!(values, key) == protected_value and not MapSet.member?(confirmed, key) do
            {:halt, {:error, {:confirmation_required, key, protected_value}}}
          else
            {:cont, :ok}
          end

        _policy ->
          {:cont, :ok}
      end
    end)
  end

  defp changed_keys(current, next) do
    current
    |> Map.keys()
    |> Enum.filter(&(Map.fetch!(current, &1) != Map.fetch!(next, &1)))
    |> Enum.sort()
  end

  defp snapshot(%Settings{} = settings) do
    with :ok <- validate_schema_version(settings.schema_version),
         {:ok, values} <- decoded_values(settings.values),
         :ok <- validate_values(values) do
      {:ok, public_snapshot(settings, values)}
    end
  end

  defp public_snapshot(settings, values) do
    %{
      scope: settings.scope,
      schema_version: settings.schema_version,
      version: settings.version,
      values: redact_secrets(values)
    }
  end

  defp decoded_values(values) when is_map(values) do
    Enum.reduce_while(values, {:ok, %{}}, fn {key, value}, {:ok, typed} ->
      case Contract.definition(key) do
        {:ok, %{storage: :encrypted_database} = definition} ->
          case decrypt_secret(definition, value) do
            {:ok, plaintext} ->
              {:cont, {:ok, Map.put(typed, definition.key, plaintext)}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        {:ok, %{storage: :database} = definition} ->
          {:cont, {:ok, Map.put(typed, definition.key, value)}}

        {:ok, _definition} ->
          {:halt, {:error, {:setting_not_persisted, key}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp decoded_values(_values), do: {:error, :invalid_stored_settings}

  defp decrypt_secret(_definition, nil), do: {:ok, nil}

  defp decrypt_secret(definition, envelope) when is_binary(envelope) do
    case SecretStore.decrypt(definition.key, envelope) do
      {:ok, plaintext} -> {:ok, plaintext}
      {:error, reason} -> {:error, {:secret_read_failed, definition.key, reason}}
    end
  end

  defp decrypt_secret(definition, _value),
    do: {:error, {:secret_read_failed, definition.key, :invalid_secret_envelope}}

  defp serialize(values, stored, changed_keys) do
    changed_keys = MapSet.new(changed_keys)

    Enum.reduce_while(Contract.database_definitions(), {:ok, %{}}, fn definition,
                                                                      {:ok, encoded} ->
      key = definition.key
      name = Atom.to_string(key)
      value = Map.fetch!(values, key)

      case encode_value(definition, value, stored, MapSet.member?(changed_keys, key)) do
        {:ok, stored_value} -> {:cont, {:ok, Map.put(encoded, name, stored_value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp encode_value(%{storage: :database}, value, _stored, _changed?), do: {:ok, value}

  defp encode_value(%{storage: :encrypted_database, key: key}, _value, stored, false),
    do: {:ok, Map.fetch!(stored, Atom.to_string(key))}

  defp encode_value(%{storage: :encrypted_database}, nil, _stored, true), do: {:ok, nil}

  defp encode_value(%{storage: :encrypted_database, key: key}, value, _stored, true) do
    case SecretStore.encrypt(key, value) do
      {:ok, envelope} -> {:ok, envelope}
      {:error, reason} -> {:error, {:secret_write_failed, key, reason}}
    end
  end

  defp redact_secrets(values) do
    Map.new(Contract.database_definitions(), fn definition ->
      value = Map.fetch!(values, definition.key)

      case definition.storage do
        :encrypted_database when is_nil(value) -> {definition.key, nil}
        :encrypted_database -> {definition.key, @redacted}
        :database -> {definition.key, value}
      end
    end)
  end

  defp revision_values(values) do
    Map.new(Contract.database_definitions(), fn definition ->
      key = Atom.to_string(definition.key)
      value = Map.fetch!(values, key)

      case definition.revision do
        :record -> {key, value}
        :redact when is_nil(value) -> {key, nil}
        :redact -> {key, @redacted}
      end
    end)
  end

  defp revision(repo, scope, version) do
    repo.one(
      from(revision in SettingsRevision,
        where: revision.settings_scope == ^scope and revision.version == ^version
      )
    )
  end

  defp revision_snapshot(revision) do
    %{
      version: revision.version,
      schema_version: revision.schema_version,
      values: revision.values,
      source: revision.source,
      metadata: revision.metadata,
      inserted_at: revision.inserted_at
    }
  end

  defp rollback_changes(revision_values, current_values) when is_map(revision_values) do
    changes =
      Contract.database_definitions()
      |> Enum.reject(&(&1.storage == :encrypted_database))
      |> Enum.reduce(%{}, fn definition, changes ->
        name = Atom.to_string(definition.key)

        case Map.fetch(revision_values, name) do
          {:ok, value} ->
            if value != Map.fetch!(current_values, definition.key),
              do: Map.put(changes, definition.key, value),
              else: changes

          :error ->
            changes
        end
      end)

    {:ok, changes}
  end

  defp rollback_changes(_revision_values, _current_values),
    do: {:error, :invalid_settings_revision}

  defp rollback_metadata(opts, target_version) do
    case Keyword.get(opts, :metadata, %{}) do
      metadata when is_map(metadata) -> {:ok, Map.put(metadata, "target_version", target_version)}
      _metadata -> {:error, :invalid_settings_metadata}
    end
  end
end
