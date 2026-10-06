defmodule JidoDelvetown.Persistence.Legacy.Startup do
  @moduledoc """
  Runs the one-time legacy imports during database startup.

  The feature flag protects both legacy settings and legacy state import. The
  settings import must run first because imported connection settings can be
  used after the rest of application startup completes.
  """

  alias JidoDelvetown.Config
  alias JidoDelvetown.Persistence.Legacy.Importer
  alias JidoDelvetown.Settings.LegacyEnvImporter

  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []) do
    if enabled?(opts) do
      with {:ok, _settings_result} <-
             LegacyEnvImporter.run(Keyword.get(opts, :settings_import_opts, [])),
           {:ok, _state_result} <- Importer.run(Keyword.get(opts, :state_import_opts, [])) do
        :ok
      end
    else
      :ok
    end
  end

  defp enabled?(opts), do: Keyword.get_lazy(opts, :enabled?, &Config.legacy_import_enabled?/0)
end
