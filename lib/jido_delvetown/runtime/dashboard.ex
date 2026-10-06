defmodule JidoDelvetown.Dashboard do
  @moduledoc "Starts the local dashboard from the active runtime settings."

  use Supervisor

  alias JidoDelvetown.Settings.Connection

  def start_link(opts \\ []) do
    settings = Keyword.get(opts, :settings, &Connection.dashboard/0)

    supervisor_opts =
      case Keyword.get(opts, :name, __MODULE__) do
        nil -> []
        name -> [name: name]
      end

    case settings.() do
      {:ok, dashboard} -> Supervisor.start_link(__MODULE__, {opts, dashboard}, supervisor_opts)
      {:error, reason} -> {:error, {:dashboard_settings_unavailable, reason}}
    end
  end

  @impl true
  def init({opts, dashboard}) do
    server = Keyword.get(opts, :server, dashboard_server())

    case dashboard do
      %{enabled?: true, port: port} ->
        Supervisor.init([{server, server_options(port)}], strategy: :one_for_one)

      %{enabled?: false} ->
        Supervisor.init([], strategy: :one_for_one)
    end
  end

  defp dashboard_server,
    do: Application.get_env(:jido_delvetown, :dashboard_server, PhoenixPlayground)

  defp server_options(port) do
    [
      live: JidoDelvetownWeb.DashboardLive,
      port: port,
      host: "localhost",
      ip: {127, 0, 0, 1},
      open_browser: false,
      live_reload: false,
      endpoint_options: [
        check_origin: ["//localhost:#{port}", "//127.0.0.1:#{port}"]
      ]
    ]
  end
end
