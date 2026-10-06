defmodule JidoDelvetown.Application do
  @moduledoc false

  use Application

  alias JidoDelvetown.{AgentBootstrap, Config, Dashboard, Database, Repo, Session}
  alias JidoDelvetown.Jido, as: JidoInstance

  @impl true
  def start(_type, _args) do
    :ok = Config.load_env()

    children = [
      Repo,
      Database,
      JidoInstance,
      {DynamicSupervisor, strategy: :one_for_one, name: JidoDelvetown.SessionSupervisor},
      Session,
      AgentBootstrap,
      {Oban, Application.fetch_env!(:jido_delvetown, Oban)},
      Dashboard
    ]

    Supervisor.start_link(children,
      strategy: :rest_for_one,
      name: JidoDelvetown.ApplicationSupervisor
    )
  end
end
