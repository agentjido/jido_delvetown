defmodule JidoDelvetown.Settings.Bootstrap do
  @moduledoc "Seeds one safe runtime configuration after database migrations finish."

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings.Contract
  alias JidoDelvetown.Storage.{Settings, SettingsRevision}

  @active_scope "active"

  @spec active_scope() :: String.t()
  def active_scope, do: @active_scope

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    scope = Keyword.get(opts, :scope, @active_scope)

    repo.transaction(fn -> seed(repo, scope) end, mode: :immediate)
  end

  defp seed(repo, scope) do
    case repo.get(Settings, scope) do
      nil -> insert_defaults(repo, scope)
      settings -> existing_settings(repo, settings)
    end
  end

  defp insert_defaults(repo, scope) do
    settings =
      %Settings{}
      |> Settings.changeset(%{
        scope: scope,
        schema_version: Contract.schema_version(),
        values: serialized_defaults()
      })
      |> repo.insert!()

    %SettingsRevision{}
    |> SettingsRevision.insert_changeset(%{
      settings_scope: settings.scope,
      version: settings.version,
      schema_version: settings.schema_version,
      values: settings.values,
      source: "bootstrap",
      metadata: %{"reason" => "safe_defaults"}
    })
    |> repo.insert!()

    result(settings, true)
  end

  defp existing_settings(repo, settings) do
    case compare_schema_versions(settings.schema_version, Contract.schema_version()) do
      :ok -> result(settings, false)
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp compare_schema_versions(version, version), do: :ok

  defp compare_schema_versions(stored, current) when stored < current,
    do: {:error, {:settings_schema_upgrade_required, stored, current}}

  defp compare_schema_versions(stored, current),
    do: {:error, {:unsupported_settings_schema, stored, current}}

  defp serialized_defaults do
    Map.new(Contract.defaults(), fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp result(settings, created?) do
    %{
      scope: settings.scope,
      schema_version: settings.schema_version,
      version: settings.version,
      created?: created?
    }
  end
end
