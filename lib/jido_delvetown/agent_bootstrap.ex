defmodule JidoDelvetown.AgentBootstrap do
  @moduledoc false

  use GenServer

  alias JidoDelvetown.Agent
  alias JidoDelvetown.Jido, as: JidoInstance

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    # Load keys from the imported checkpoint format before Jido performs its
    # safe decode. The next checkpoint stores state as JSON.
    Code.ensure_loaded!(Jido.Agent.Checkpoint)
    Code.ensure_loaded!(JidoDelvetown.Actions.RecordCycle)

    case JidoInstance.start_agent(Agent,
           id: Agent.id(),
           debug: true,
           turn_timeout: 120_000,
           restart: :transient
         ) do
      {:ok, agent_server} -> {:ok, %{agent_server: agent_server}}
      {:error, reason} -> {:stop, {:agent_start_failed, reason}}
    end
  end
end
