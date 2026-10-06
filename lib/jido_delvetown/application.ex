defmodule JidoDelvetown.Application do
  @moduledoc false

  use Application

  alias JidoDelvetown.{AgentBootstrap, Config, Database, Repo, Session}
  alias JidoDelvetown.Jido, as: JidoInstance

  @impl true
  def start(_type, _args) do
    :ok = Config.load_env()

    children =
      [
        Repo,
        Database,
        JidoInstance,
        {DynamicSupervisor, strategy: :one_for_one, name: JidoDelvetown.SessionSupervisor},
        Session,
        AgentBootstrap,
        {Oban, Application.fetch_env!(:jido_delvetown, Oban)}
      ] ++ dashboard_children()

    Supervisor.start_link(children,
      strategy: :rest_for_one,
      name: JidoDelvetown.ApplicationSupervisor
    )
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
