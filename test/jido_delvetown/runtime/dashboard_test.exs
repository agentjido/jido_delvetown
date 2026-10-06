defmodule JidoDelvetown.DashboardTest do
  use ExUnit.Case, async: true

  alias JidoDelvetown.Dashboard
  alias JidoDelvetown.Test.DashboardServer

  test "does not start a dashboard server when the SQLite setting is disabled" do
    dashboard =
      start_supervised!(
        {Dashboard,
         name: nil,
         server: DashboardServer,
         settings: fn -> {:ok, %{enabled?: false, port: 4_141}} end}
      )

    assert Supervisor.which_children(dashboard) == []
  end

  test "starts the dashboard server with the configured SQLite port" do
    dashboard =
      start_supervised!(
        {Dashboard,
         name: nil,
         server: DashboardServer,
         settings: fn -> {:ok, %{enabled?: true, port: 4_141}} end}
      )

    assert [{DashboardServer, server, :worker, [DashboardServer]}] =
             Supervisor.which_children(dashboard)

    options = :sys.get_state(server)
    assert options[:port] == 4_141

    assert options[:endpoint_options][:check_origin] == [
             "//localhost:4141",
             "//127.0.0.1:4141"
           ]
  end

  test "stops startup when the runtime settings cannot be read" do
    assert {:error, {:dashboard_settings_unavailable, :database_unavailable}} =
             Dashboard.start_link(
               name: nil,
               server: DashboardServer,
               settings: fn -> {:error, :database_unavailable} end
             )
  end
end
