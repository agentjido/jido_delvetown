defmodule JidoDelvetown.Participation.CycleRunnerTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Agent
  alias JidoDelvetown.Participation.CycleRunner

  defmodule FakeAgentLocator do
    def whereis_agent(agent_id) do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), {:locate_agent, agent_id})
      Application.fetch_env!(:jido_delvetown, :agent_locator_result)
    end
  end

  defmodule FakeAgentServer do
    def call(agent_server, signal, options) do
      send(
        Application.fetch_env!(:jido_delvetown, :test_owner),
        {:agent_call, agent_server, signal.type, signal.source, options}
      )

      {:ok, %{state: %{last_run: %{signal: signal.type}}}}
    end
  end

  defmodule FakeCycleRunner do
    def agent_server, do: record(:agent_server, {:ok, self()})
    def run_reactive, do: record(:run_reactive)
    def review_reactive, do: record(:review_reactive)
    def run_proactive, do: record(:run_proactive)
    def review_proactive, do: record(:review_proactive)
    def run_member_discovery, do: record(:run_member_discovery)
    def review_member_discovery, do: record(:review_member_discovery)

    defp record(function), do: record(function, {:ok, %{function: function}})

    defp record(function, result) do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), {:cycle_runner, function})
      result
    end
  end

  setup do
    old_owner = Application.get_env(:jido_delvetown, :test_owner)
    old_locator = Application.get_env(:jido_delvetown, :participation_agent_locator)
    old_agent_server = Application.get_env(:jido_delvetown, :participation_agent_server)
    old_locator_result = Application.get_env(:jido_delvetown, :agent_locator_result)
    old_cycle_runner = Application.get_env(:jido_delvetown, :cycle_runner)

    Application.put_env(:jido_delvetown, :test_owner, self())
    Application.put_env(:jido_delvetown, :participation_agent_locator, FakeAgentLocator)
    Application.put_env(:jido_delvetown, :participation_agent_server, FakeAgentServer)
    Application.put_env(:jido_delvetown, :agent_locator_result, self())

    on_exit(fn ->
      restore_env(:test_owner, old_owner)
      restore_env(:participation_agent_locator, old_locator)
      restore_env(:participation_agent_server, old_agent_server)
      restore_env(:agent_locator_result, old_locator_result)
      restore_env(:cycle_runner, old_cycle_runner)
    end)

    :ok
  end

  test "owns agent lookup and all participation signal calls" do
    assert {:ok, agent_server} = CycleRunner.agent_server()
    assert agent_server == self()
    assert_receive {:locate_agent, agent_id}
    assert agent_id == Agent.id()

    calls = [
      run_reactive: "jido.delvetown.reactive",
      review_reactive: "jido.delvetown.reactive.review",
      run_proactive: "jido.delvetown.proactive",
      review_proactive: "jido.delvetown.proactive.review",
      run_member_discovery: "jido.delvetown.members",
      review_member_discovery: "jido.delvetown.members.review"
    ]

    for {function, signal_type} <- calls do
      assert {:ok, %{signal: ^signal_type}} = apply(CycleRunner, function, [])
      assert_receive {:locate_agent, ^agent_id}

      assert_receive {:agent_call, ^agent_server, ^signal_type, "/jido_delvetown/operator",
                      [timeout: 120_000]}
    end
  end

  test "returns the existing error when the agent is not running" do
    Application.put_env(:jido_delvetown, :agent_locator_result, nil)

    assert {:error, :agent_not_running} = CycleRunner.run_reactive()
    assert_receive {:locate_agent, _agent_id}
    refute_receive {:agent_call, _agent_server, _signal_type, _source, _options}
  end

  test "the public facade delegates operator cycle functions to the owner" do
    Application.put_env(:jido_delvetown, :cycle_runner, FakeCycleRunner)

    assert {:ok, agent_server} = JidoDelvetown.agent_server()
    assert agent_server == self()
    assert_receive {:cycle_runner, :agent_server}

    calls = [
      run_now: :run_reactive,
      review: :review_reactive,
      run_reactive: :run_reactive,
      review_reactive: :review_reactive,
      run_proactive: :run_proactive,
      review_proactive: :review_proactive,
      run_member_discovery: :run_member_discovery,
      review_member_discovery: :review_member_discovery,
      suggest_proactive: :review_proactive
    ]

    for {public_function, owner_function} <- calls do
      assert {:ok, %{function: ^owner_function}} = apply(JidoDelvetown, public_function, [])
      assert_receive {:cycle_runner, ^owner_function}
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_delvetown, key)
  defp restore_env(key, value), do: Application.put_env(:jido_delvetown, key, value)
end
