defmodule JidoDelvetown do
  @moduledoc "IEx operator interface for the Jido Delvetown tracer."

  alias JidoDelvetown.Agent
  alias JidoDelvetown.Config
  alias JidoDelvetown.Personality
  alias JidoDelvetown.Session
  alias JidoDelvetown.Store
  alias JidoDelvetown.Transport.ProtoRune, as: Transport

  def connect, do: Session.connect()
  def disconnect, do: Session.disconnect()

  def agent_server do
    case JidoDelvetown.Jido.whereis_agent(Agent.id()) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {:error, :agent_not_running}
      {:error, _reason} = error -> error
    end
  end

  def run_now, do: run_reactive()
  def review, do: review_reactive()

  def run_reactive, do: run_cycle("jido.delvetown.reactive")
  def review_reactive, do: run_cycle("jido.delvetown.reactive.review")
  def run_proactive, do: run_cycle("jido.delvetown.proactive")
  def review_proactive, do: run_cycle("jido.delvetown.proactive.review")
  def suggest_proactive, do: review_proactive()

  def ask_operator(query) when is_binary(query) and query != "" do
    with {:ok, agent_server} <- agent_server() do
      Agent.ask_sync(agent_server, query, profile: :operator, timeout: 120_000)
    end
  end

  def membership do
    with {:ok, session} <- Session.session() do
      Transport.get_membership(session, [])
    end
  end

  def disclosure, do: Personality.disclosure()
  def profile_disclosure, do: Personality.profile_disclosure()

  def join(invite_code \\ nil) do
    with true <- Config.write_enabled?() || {:error, :writes_disabled},
         {:ok, session} <- Session.session(),
         {:ok, configured_code} <- configured_invite(invite_code) do
      Transport.join(session, configured_code, [])
    end
  end

  def label_bot, do: label_bot(profile_disclosure())

  def label_bot(description) when is_binary(description) do
    with true <- Config.write_enabled?() || {:error, :writes_disabled},
         :ok <- validate_description(description),
         {:ok, session} <- Session.session() do
      Transport.label_bot(session, description, [])
    end
  end

  def status do
    with {:ok, agent_server} <- agent_server() do
      agent = Jido.AgentServer.agent(agent_server)

      %{
        session: Session.status(),
        store: Store.counts(),
        schedule_enabled?: map_size(agent.state.scheduler.cron) > 0,
        cron: configured_scheduler_options()[:cron_expression],
        writes_enabled?: Config.write_enabled?(),
        mark_notifications_seen?: Config.mark_notifications_seen?(),
        budget: agent.state.budget,
        decision: agent.state.decision,
        last_cycle: agent.state.last_cycle,
        last_run: agent.state.last_run,
        credentials_configured?: match?({:ok, _credentials}, Config.credentials())
      }
    end
  end

  def recent_events(limit \\ 25) do
    with {:ok, agent_server} <- agent_server() do
      %{
        workflow: Store.recent_events(Store, limit),
        agent: Jido.AgentServer.recent_events(agent_server, limit: limit)
      }
    end
  end

  defp configured_invite(invite_code) when is_binary(invite_code) and invite_code != "",
    do: {:ok, invite_code}

  defp configured_invite(_invite_code) do
    case Config.invite_code() do
      {:ok, code} -> {:ok, code}
      {:error, _reason} -> {:ok, nil}
    end
  end

  defp validate_description(description) do
    cond do
      String.length(description) > 256 ->
        {:error, :description_too_long}

      not String.contains?(String.downcase(description), ["ai", "automated", "bot"]) ->
        {:error, :automation_disclosure_required}

      true ->
        :ok
    end
  end

  defp run_cycle(type) do
    with {:ok, agent_server} <- agent_server(),
         signal = Jido.Signal.new!(type, %{}, source: "/jido_delvetown/operator"),
         {:ok, agent} <- Jido.AgentServer.call(agent_server, signal, timeout: 120_000) do
      {:ok, agent.state.last_run}
    end
  end

  defp configured_scheduler_options do
    Agent.definition().plugins
    |> Enum.find_value([], fn
      {Jido.Plugin.Scheduler, options} -> options
      _plugin -> nil
    end)
  end
end
