defmodule JidoDelvetown.FollowEngagementTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{Agent, Protocol, ReactiveParticipationCycle, Repo}
  alias JidoDelvetown.Storage.{Actor, Effect, InteractionEvent, ScanState}
  alias JidoDelvetown.Test.{FakeDecision, FakeSession, FakeTransport}

  setup do
    Enum.each([ScanState, InteractionEvent, Actor, Effect], &Repo.delete_all/1)

    keys = [
      :session_module,
      :transport,
      :decision_module,
      :query_results,
      :decision_result,
      :create_result,
      :get_result,
      :test_owner
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:jido_delvetown, &1)})
    old_write = System.get_env("DELVETOWN_WRITE_ENABLED")

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :decision_module, FakeDecision)
    Application.put_env(:jido_delvetown, :test_owner, self())
    System.put_env("DELVETOWN_WRITE_ENABLED", "true")

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:jido_delvetown, key)
        {key, value} -> Application.put_env(:jido_delvetown, key, value)
      end)

      restore_env("DELVETOWN_WRITE_ENABLED", old_write)
    end)

    :ok
  end

  test "a new follow can produce one follow-back effect" do
    configure_follow("follow-1")
    decide("follow")

    assert {:ok, state} = run()
    assert state.last_run.intent == "respond_to_new_follow"
    assert state.last_run.status == "acted"

    assert_received {:decision, "respond_to_new_follow", payload}
    assert payload.candidate.author.did == "did:plc:follower"
    assert payload.candidate.memory.actor == nil

    assert_received {:create_record, "town.delve.graph.follow", record, rkey}
    assert record.subject == "did:plc:follower"
    assert is_binary(rkey)

    key = Protocol.effect_key("follow", ["did:plc:follower"])
    assert %Effect{status: "completed", actor_did: "did:plc:follower"} = Repo.get(Effect, key)
    assert %Actor{contact_count: 1} = Repo.get(Actor, "did:plc:follower")
  end

  test "a repeated notification is not selected again after restart" do
    configure_follow("follow-repeat")
    decide("acknowledge")

    assert {:ok, first_state} = run()
    assert first_state.last_run.status == "acknowledged"
    assert_received {:decision, "respond_to_new_follow", _payload}

    assert {:ok, second_state} = run(Agent.new!().state)
    assert second_state.last_run.status == "skipped"
    refute_received {:decision, _intent, _payload}
    assert Repo.get!(InteractionEvent, "notification:follow-repeat").attempt_count == 1
  end

  test "an unfollow and later follow does not repeat contact" do
    configure_follow("follow-first")
    decide("follow")
    assert {:ok, _state} = run()
    assert_received {:decision, "respond_to_new_follow", _payload}
    assert_received {:create_record, "town.delve.graph.follow", _record, _rkey}

    configure_follow("follow-again")
    assert {:ok, state} = run(Agent.new!().state)

    assert state.last_run.status == "skipped"
    assert state.last_run.proposal.reason == "follow_actor_already_contacted"
    refute_received {:decision, _intent, _payload}
    refute_received {:create_record, "town.delve.graph.follow", _record, _rkey}
  end

  test "a lost follow response is reconciled with the same record key" do
    configure_follow("follow-reconcile")
    decide("follow")
    Application.put_env(:jido_delvetown, :create_result, {:error, :timeout})

    Application.put_env(
      :jido_delvetown,
      :get_result,
      {:ok, %{uri: "at://did:plc:bot/town.delve.graph.follow/stable", cid: "follow-cid"}}
    )

    assert {:ok, state} = run()
    assert state.last_run.status == "acted"
    assert state.last_run.effects == 1

    assert_received {:create_record, "town.delve.graph.follow", _record, rkey}
    assert_received {:get_record, "town.delve.graph.follow", ^rkey}

    key = Protocol.effect_key("follow", ["did:plc:follower"])
    assert %Effect{status: "completed", attempt_count: 1} = Repo.get(Effect, key)
  end

  test "a welcome uses the actor DID as one stable public effect" do
    configure_follow("follow-welcome")
    decide("welcome", "Welcome. The OTP failure-boundary threads may be useful to you.")

    assert {:ok, state} = run()
    assert state.last_run.status == "acted"

    key = Protocol.effect_key("welcome", ["did:plc:follower"])

    assert %Effect{
             status: "completed",
             kind: "welcome",
             subject_key: "did:plc:follower",
             actor_did: "did:plc:follower"
           } = Repo.get(Effect, key)

    assert Repo.get!(Actor, "did:plc:follower").welcome_status == "completed"
  end

  defp run(state \\ Agent.new!().state) do
    Jido.Exec.run(
      ReactiveParticipationCycle,
      %{mode: "normal"},
      %{agent_state: state}
    )
  end

  defp configure_follow(id) do
    Application.put_env(:jido_delvetown, :query_results, %{
      "town.delve.membership.getMembership" => {:ok, %{"status" => "member"}},
      "town.delve.notification.listNotifications" =>
        {:ok,
         %{
           "notifications" => [
             %{
               "id" => id,
               "reason" => "follow",
               "isRead" => false,
               "indexedAt" => "2026-10-05T12:00:00Z",
               "author" => %{
                 "did" => "did:plc:follower",
                 "handle" => "follower.test",
                 "displayName" => "Follower"
               }
             }
           ]
         }}
    })
  end

  defp decide(action, text \\ nil) do
    Application.put_env(
      :jido_delvetown,
      :decision_result,
      {:ok,
       %{
         action: action,
         text: text,
         topic: "new follower",
         reason: "Bounded follow response"
       }}
    )
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
