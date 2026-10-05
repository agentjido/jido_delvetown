defmodule JidoDelvetown.Application do
  @moduledoc false

  use Application

  alias JidoDelvetown.{Agent, Config, Session, Store}
  alias JidoDelvetown.Jido, as: JidoInstance

  @impl true
  def start(_type, _args) do
    :ok = Config.load_env()

    children = [
      JidoInstance,
      Store,
      {DynamicSupervisor, strategy: :one_for_one, name: JidoDelvetown.SessionSupervisor},
      Session
    ]

    with {:ok, supervisor} <-
           Supervisor.start_link(children,
             strategy: :rest_for_one,
             name: JidoDelvetown.ApplicationSupervisor
           ) do
      case start_agent() do
        :ok ->
          {:ok, supervisor}

        {:error, reason} ->
          Supervisor.stop(supervisor)
          {:error, {:agent_start_failed, reason}}
      end
    end
  end

  defp start_agent do
    # Load keys from the first local checkpoint format before Jido performs its
    # safe decode. The next checkpoint stores state as JSON and does not need
    # this compatibility load.
    Code.ensure_loaded!(Jido.Agent.Checkpoint)
    Code.ensure_loaded!(JidoDelvetown.Actions.RecordCycle)

    case JidoInstance.start_agent(Agent,
           id: Agent.id(),
           debug: true,
           turn_timeout: 120_000,
           restart: :transient
         ) do
      {:ok, _agent_server} -> :ok
      {:error, _reason} = error -> error
    end
  end
end
