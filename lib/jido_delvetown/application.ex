defmodule JidoDelvetown.Application do
  @moduledoc false

  use Application

  alias JidoDelvetown.{Agent, Config, Database, Repo, Session, Store}
  alias JidoDelvetown.Jido, as: JidoInstance

  @impl true
  def start(_type, _args) do
    :ok = Config.load_env()

    children =
      [
        Repo,
        Database,
        JidoInstance,
        Store,
        {DynamicSupervisor, strategy: :one_for_one, name: JidoDelvetown.SessionSupervisor},
        Session
      ] ++ dashboard_children()

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
      {:ok, agent_server} -> ensure_schedule(agent_server)
      {:error, _reason} = error -> error
    end
  end

  defp ensure_schedule(agent_server) do
    signal =
      Jido.Signal.new!("jido.delvetown.schedule.ensure", %{},
        source: "/jido_delvetown/application"
      )

    case Jido.AgentServer.call(agent_server, signal, timeout: 10_000) do
      {:ok, _agent} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp dashboard_children do
    if Config.dashboard_enabled?() do
      port = Config.dashboard_port()

      [
        {PhoenixPlayground,
         live: JidoDelvetownWeb.DashboardLive,
         port: port,
         host: "localhost",
         ip: {127, 0, 0, 1},
         open_browser: false,
         live_reload: false,
         endpoint_options: [
           check_origin: ["//localhost:#{port}", "//127.0.0.1:#{port}"]
         ]}
      ]
    else
      []
    end
  end
end
