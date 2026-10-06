defmodule JidoDelvetown.Settings do
  @moduledoc """
  Reads and changes the active runtime settings.

  Each successful change updates the active row and adds one immutable revision
  in the same SQLite transaction. Callers can supply `:expected_version` to
  reject stale writes. Protected values also require their key in `:confirmed`.
  """

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings.{Bootstrap, Contract}
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

  @spec update(map() | keyword(), keyword()) :: {:ok, snapshot()} | {:error, term()}
  def update(changes, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    scope = Keyword.get(opts, :scope, Bootstrap.active_scope())

    with {:ok, changes} <- normalize_changes(changes),
         {:ok, update_opts} <- normalize_update_opts(opts) do
      repo.transaction(
        fn -> update_transaction(repo, scope, changes, update_opts) end,
        mode: :immediate
      )
    end
  end

  defp update_transaction(repo, scope, changes, opts) do
    with %Settings{} = settings <- repo.get(Settings, scope),
         :ok <- validate_schema_version(settings.schema_version),
         :ok <- validate_expected_version(settings.version, opts.expected_version),
         {:ok, current_values} <- typed_values(settings.values),
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

  defp persist_update(_repo, settings, values, [], _opts), do: snapshot!(settings, values)

  defp persist_update(repo, settings, values, _changed_keys, opts) do
    serialized = serialize(values)

    with {:ok, updated} <-
           settings
           |> Settings.changeset(%{values: serialized})
           |> repo.update(),
         {:ok, _revision} <- insert_revision(repo, updated, opts) do
      snapshot!(updated, values)
    else
      {:error, changeset} -> repo.rollback({:settings_write_failed, changeset})
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
             :ok <- ensure_writable(definition, value),
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

  defp ensure_writable(%{storage: :encrypted_database, key: key}, value)
       when not is_nil(value),
       do: {:error, {:secure_storage_required, key}}

  defp ensure_writable(_definition, _value), do: :ok

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
         {:ok, values} <- typed_values(settings.values),
         :ok <- validate_values(values) do
      {:ok, snapshot!(settings, values)}
    end
  end

  defp snapshot!(settings, values) do
    %{
      scope: settings.scope,
      schema_version: settings.schema_version,
      version: settings.version,
      values: values
    }
  end

  defp typed_values(values) when is_map(values) do
    Enum.reduce_while(values, {:ok, %{}}, fn {key, value}, {:ok, typed} ->
      case Contract.definition(key) do
        {:ok, definition} when definition.storage in [:database, :encrypted_database] ->
          {:cont, {:ok, Map.put(typed, definition.key, value)}}

        {:ok, _definition} ->
          {:halt, {:error, {:setting_not_persisted, key}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp typed_values(_values), do: {:error, :invalid_stored_settings}

  defp serialize(values),
    do: Map.new(values, fn {key, value} -> {Atom.to_string(key), value} end)

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
end
