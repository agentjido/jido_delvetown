defmodule JidoDelvetown.Participation.CycleRunner do
  @moduledoc false

  alias JidoDelvetown.Agent

  @source "/jido_delvetown/operator"
  @timeout 120_000

  @spec agent_server() :: {:ok, pid()} | {:error, term()}
  def agent_server do
    case agent_locator().whereis_agent(Agent.id()) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {:error, :agent_not_running}
      {:error, _reason} = error -> error
    end
  end

  @spec run_reactive() :: {:ok, map()} | {:error, term()}
  def run_reactive, do: run_cycle("jido.delvetown.reactive")

  @spec review_reactive() :: {:ok, map()} | {:error, term()}
  def review_reactive, do: run_cycle("jido.delvetown.reactive.review")

  @spec run_proactive() :: {:ok, map()} | {:error, term()}
  def run_proactive, do: run_cycle("jido.delvetown.proactive")

  @spec review_proactive() :: {:ok, map()} | {:error, term()}
  def review_proactive, do: run_cycle("jido.delvetown.proactive.review")

  @spec run_member_discovery() :: {:ok, map()} | {:error, term()}
  def run_member_discovery, do: run_cycle("jido.delvetown.members")

  @spec review_member_discovery() :: {:ok, map()} | {:error, term()}
  def review_member_discovery, do: run_cycle("jido.delvetown.members.review")

  defp run_cycle(type) do
    with {:ok, agent_server} <- agent_server(),
         signal = Jido.Signal.new!(type, %{}, source: @source),
         {:ok, agent} <-
           agent_server_runtime().call(agent_server, signal, timeout: @timeout) do
      {:ok, agent.state.last_run}
    end
  end

  defp agent_locator do
    Application.get_env(
      :jido_delvetown,
      :participation_agent_locator,
      JidoDelvetown.Jido
    )
  end

  defp agent_server_runtime do
    Application.get_env(
      :jido_delvetown,
      :participation_agent_server,
      Jido.AgentServer
    )
  end
end
