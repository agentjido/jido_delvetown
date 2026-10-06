defmodule JidoDelvetown do
  @moduledoc "IEx operator interface for the Jido Delvetown tracer."

  alias JidoDelvetown.Agent
  alias JidoDelvetown.Automation
  alias JidoDelvetown.Config
  alias JidoDelvetown.FriendList
  alias JidoDelvetown.FriendSync
  alias JidoDelvetown.Inspection
  alias JidoDelvetown.Personality
  alias JidoDelvetown.Participation.CycleRunner
  alias JidoDelvetown.Session
  alias JidoDelvetown.Store
  alias JidoDelvetown.Transport.ProtoRune, as: Transport

  def connect, do: Session.connect()
  def disconnect, do: Session.disconnect()

  def agent_server do
    cycle_runner().agent_server()
  end

  def run_now, do: run_reactive()
  def review, do: review_reactive()

  def run_reactive, do: cycle_runner().run_reactive()
  def review_reactive, do: cycle_runner().review_reactive()
  def run_proactive, do: cycle_runner().run_proactive()
  def review_proactive, do: cycle_runner().review_proactive()
  def run_member_discovery, do: cycle_runner().run_member_discovery()
  def review_member_discovery, do: cycle_runner().review_member_discovery()
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
  def inspect_state(opts \\ []), do: Inspection.snapshot(opts)

  def friends, do: FriendList.list()
  def friend(did), do: FriendList.get(did)
  def add_friend(actor, attrs \\ %{}), do: FriendList.add(actor, attrs)
  def remove_friend(did), do: FriendList.remove(did)
  def record_friend_reference(did), do: FriendList.record_reference(did)
  def sync_friends, do: FriendSync.sync()

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
        schedule_enabled?: Automation.running?(),
        cron: Automation.reactive_cron(),
        proactive_review_cron: Automation.proactive_review_cron(),
        friend_sync_cron: Automation.friend_sync_cron(),
        writes_enabled?: Config.write_enabled?(),
        manual_publish_enabled?: Config.manual_publish_enabled?(),
        dry_run_mark_actioned?: Config.dry_run_mark_actioned?(),
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

  defp cycle_runner,
    do: Application.get_env(:jido_delvetown, :cycle_runner, CycleRunner)
end
