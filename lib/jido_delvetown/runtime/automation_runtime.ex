defmodule JidoDelvetown.AutomationRuntime do
  @moduledoc "Keeps the Oban Cron process aligned with the active SQLite schedules."

  use Supervisor

  alias JidoDelvetown.Settings.Schedules
  alias Oban.Config

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec reconcile([{String.t(), module()}]) :: :ok | {:error, term()}
  def reconcile(crontab) when is_list(crontab) do
    case :global.trans({__MODULE__, :reconcile}, fn -> replace_cron(crontab) end) do
      :ok -> :ok
      {:error, _reason} = error -> error
      {:aborted, reason} -> {:error, {:schedule_reconcile_lock_failed, reason}}
      other -> {:error, {:unexpected_schedule_reconcile_result, other}}
    end
  end

  @impl Supervisor
  def init(_opts) do
    with {:ok, crontab} <- Schedules.crontab(),
         %Config{} = conf <- Oban.config() do
      Supervisor.init([cron_spec(conf, crontab)], strategy: :one_for_one)
    else
      {:error, reason} -> {:stop, {:schedule_reconcile_failed, reason}}
      _invalid -> {:stop, {:schedule_reconcile_failed, :oban_config_unavailable}}
    end
  end

  defp replace_cron(crontab) do
    with %Config{} = conf <- Oban.config(),
         :ok <- stop_cron(),
         :ok <- start_cron(conf, crontab) do
      :ok
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :oban_config_unavailable}
    end
  rescue
    error -> {:error, {:schedule_reconcile_failed, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:schedule_reconcile_failed, reason}}
  end

  defp stop_cron do
    case Supervisor.terminate_child(__MODULE__, Oban.Cron) do
      :ok -> delete_cron()
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, {:cron_stop_failed, reason}}
    end
  end

  defp delete_cron do
    case Supervisor.delete_child(__MODULE__, Oban.Cron) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, {:cron_delete_failed, reason}}
    end
  end

  defp start_cron(conf, crontab) do
    case Supervisor.start_child(__MODULE__, cron_spec(conf, crontab)) do
      {:ok, _pid} -> :ok
      {:ok, _pid, _info} -> :ok
      {:error, reason} -> {:error, {:cron_start_failed, reason}}
    end
  end

  defp cron_spec(conf, crontab) do
    name = Oban.Registry.via(conf.name, {:plugin, Oban.Cron})
    opts = [conf: conf, name: name, crontab: crontab]

    Supervisor.child_spec({Oban.Cron, opts}, id: Oban.Cron)
  end
end
