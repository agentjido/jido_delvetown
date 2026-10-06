defmodule JidoDelvetown.DirectEngagementTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{
    Agent,
    ProactiveParticipationCycle,
    ReactiveParticipationCycle,
    Repo,
    ScanProgress
  }

  alias JidoDelvetown.Storage.{Actor, Conversation, Effect, InteractionEvent, ScanState}
  alias JidoDelvetown.Test.{FakeDecision, FakeSession, FakeTransport, RuntimeSettings}

  setup do
    Enum.each([ScanState, InteractionEvent, Conversation, Actor, Effect], &Repo.delete_all/1)

    keys = [
      :session_module,
      :transport,
      :decision_module,
      :query_results,
      :decision_result,
      :test_owner
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:jido_delvetown, &1)})
    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :decision_module, FakeDecision)
    Application.put_env(:jido_delvetown, :test_owner, self())

    restore_settings =
      RuntimeSettings.preserve!(
        autonomy_mode: "observe",
        dry_run_mark_actioned: false,
        daily_reply_limit: 3
      )

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:jido_delvetown, key)
        {key, value} -> Application.put_env(:jido_delvetown, key, value)
      end)

      restore_settings.()
    end)

    :ok
  end

  test "a direct mention includes its thread and durable memory" do
    notification = notification("mention-1", "mention", "Can a supervisor own this failure?")
    configure_reactive(notification)
    reply_decision()

    assert {:ok, state} = run_reactive()
    assert state.last_run.intent == "answer_direct_request"

    assert_received {:decision, "answer_direct_request", payload}
    assert payload.candidate.reason == "mention"
    assert payload.candidate.thread.post.text == notification["record"]["text"]
    assert payload.candidate.memory == %{actor: nil, conversation: nil}
  end

  test "a reply read in Delvetown remains eligible while its local event is pending" do
    notification =
      "reply-read-remotely"
      |> notification("reply", "Can local memory own this event?")
      |> Map.put("isRead", true)

    configure_reactive(notification)
    reply_decision()

    assert {:ok, state} = run_reactive()
    assert state.last_run.intent == "answer_direct_request"
    assert state.last_run.candidate_id == "reply-read-remotely"
    assert_received {:decision, "answer_direct_request", _payload}
  end

  test "a simulated direct event is not selected again" do
    RuntimeSettings.update!(dry_run_mark_actioned: true)
    notification = notification("reply-repeat", "reply", "How should I retry this?")
    configure_reactive(notification)
    reply_decision()

    assert {:ok, first_state} = run_reactive()
    assert first_state.last_run.status == "simulated"
    assert_received {:decision, "answer_direct_request", _payload}

    assert {:ok, state} = run_reactive()
    assert state.last_run.status == "skipped"
    assert state.last_run.summary =~ "skip"
    refute_received {:decision, _intent, _payload}
    assert Repo.get!(InteractionEvent, "notification:reply-repeat").attempt_count == 1
  end

  test "review mode keeps a normal cycle pending when simulation is enabled" do
    RuntimeSettings.update!(autonomy_mode: "review", dry_run_mark_actioned: true)
    notification = notification("reply-review", "reply", "Can I review this first?")
    configure_reactive(notification)
    reply_decision()

    assert {:ok, state} = run_reactive()
    assert state.last_run.status == "proposed"
    assert state.budget.replies == 0
    assert Repo.get!(InteractionEvent, "notification:reply-review").state == "pending"
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "simulation consumes an earlier pending proposal" do
    notification = notification("reply-transition", "reply", "Can this proposal advance?")
    configure_reactive(notification)
    reply_decision()

    assert {:ok, proposed_state} = run_reactive()
    assert proposed_state.last_run.status == "proposed"
    assert Repo.get!(InteractionEvent, "notification:reply-transition").state == "pending"

    RuntimeSettings.update!(dry_run_mark_actioned: true)

    assert {:ok, simulated_state} = run_reactive(proposed_state)
    assert simulated_state.last_run.status == "simulated"
    assert Repo.get!(InteractionEvent, "notification:reply-transition").state == "completed"
  end

  test "a later turn includes actor and conversation memory" do
    RuntimeSettings.update!(autonomy_mode: "autonomous")
    reply_decision()

    first = notification("turn-1", "reply", "Where should this process live?", "first")
    configure_reactive(first)
    assert {:ok, first_state} = run_reactive()
    assert first_state.last_run.status == "acted"
    assert_received {:decision, "answer_direct_request", first_payload}

    second = notification("turn-2", "reply", "What should restart it?", "second")
    configure_reactive(second)
    assert {:ok, second_state} = run_reactive(first_state)
    assert second_state.last_run.status == "acted"

    assert_received {:decision, "continue_conversation", payload}
    refute payload.response_format.id == first_payload.response_format.id
    assert payload.candidate.memory.actor.contact_count == 1
    assert payload.candidate.memory.conversation.turn_count == 1
    assert payload.candidate.memory.conversation.last_action == "reply"

    assert Repo.get!(Actor, "did:plc:member").contact_count == 2
    assert Repo.get!(Conversation, root_uri()).turn_count == 2
    assert length(second_state.voice.recent_formats) == 2
  end

  test "an opt-out request is stored and prevents later contact" do
    first = notification("opt-out-1", "mention", "Please do not reply to me.")
    configure_reactive(first)

    assert {:ok, state} = run_reactive()
    assert state.last_run.action == "skip"
    assert state.last_run.proposal.reason == "actor_opt_out"
    refute_received {:decision, _intent, _payload}
    assert Repo.get!(Actor, "did:plc:member").opted_out
    assert Repo.get!(InteractionEvent, "notification:opt-out-1").state == "ignored"

    second = notification("opt-out-2", "reply", "Can you answer now?", "later")
    configure_reactive(second)

    assert {:ok, next_state} = run_reactive(state)
    assert next_state.last_run.proposal.reason == "actor_opt_out"
    refute_received {:decision, _intent, _payload}
  end

  test "the daily limit leaves a direct event pending for a later cycle" do
    RuntimeSettings.update!(daily_reply_limit: 0)
    notification = notification("limited-1", "reply", "Can you explain this limit?")
    configure_reactive(notification)

    assert {:ok, state} = run_reactive()
    assert state.last_run.proposal.reason == "reply_budget_exhausted"
    assert Repo.get!(InteractionEvent, "notification:limited-1").state == "pending"
    refute_received {:decision, _intent, _payload}
  end

  test "pending direct work has priority over proactive work" do
    assert {:ok, _event} =
             JidoDelvetown.InteractionLedger.observe(%{
               event_key: "notification:waiting",
               kind: "mention"
             })

    configure_proactive()

    assert {:ok, state} =
             Jido.Exec.run(
               ProactiveParticipationCycle,
               %{mode: "normal"},
               %{agent_state: Agent.new!().state}
             )

    assert state.last_run.action == "skip"
    assert state.last_run.proposal.reason == "direct_request_pending"
    refute_received {:decision, _intent, _payload}
  end

  test "a notification page drains every direct event before its cursor advances" do
    RuntimeSettings.update!(dry_run_mark_actioned: true)
    assert {:ok, _scan} = ScanProgress.put_cursor("notifications", "page-1")

    first = notification("page-reply-1", "reply", "Where should this process live?", "one")
    second = notification("page-reply-2", "reply", "What should restart it?", "two")

    Application.put_env(:jido_delvetown, :query_results, %{
      "town.delve.membership.getMembership" => {:ok, %{"status" => "member"}},
      "town.delve.notification.listNotifications" =>
        {:ok, %{"cursor" => "page-2", "notifications" => [first, second]}},
      "town.delve.feed.getPostThread" =>
        {:ok,
         %{
           "thread" => %{
             "post" => %{
               "uri" => first["uri"],
               "cid" => first["cid"],
               "record" => %{"text" => first["record"]["text"]}
             },
             "replies" => []
           }
         }}
    })

    reply_decision()

    assert {:ok, first_state} = run_reactive()
    assert first_state.last_run.status == "simulated"
    assert ScanProgress.get("notifications").cursor == "page-1"

    first_page_events = [
      Repo.get!(InteractionEvent, "notification:page-reply-1"),
      Repo.get!(InteractionEvent, "notification:page-reply-2")
    ]

    assert Enum.frequencies_by(first_page_events, & &1.state) == %{
             "completed" => 1,
             "pending" => 1
           }

    assert {:ok, drained_state} = run_reactive(first_state)
    assert drained_state.last_run.status == "simulated"
    assert ScanProgress.get("notifications").cursor == "page-2"

    Enum.each(["notification:page-reply-1", "notification:page-reply-2"], fn event_key ->
      event = Repo.get!(InteractionEvent, event_key)
      assert event.state == "completed"
      assert event.attempt_count == 1
    end)

    refute JidoDelvetown.InteractionEvents.pending?(["mention", "reply"])

    timeline_uri = "at://did:plc:timeline-author/town.delve.feed.post/question"
    indexed_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    Application.put_env(:jido_delvetown, :query_results, %{
      "town.delve.membership.getMembership" => {:ok, %{"status" => "member"}},
      "town.delve.feed.getTimeline" =>
        {:ok,
         %{
           "feed" => [
             %{
               "post" => %{
                 "uri" => timeline_uri,
                 "cid" => "timeline-question-cid",
                 "indexedAt" => indexed_at,
                 "author" => %{
                   "did" => "did:plc:timeline-author",
                   "handle" => "timeline-author.test"
                 },
                 "viewer" => %{},
                 "labels" => [],
                 "record" => %{"text" => "Which process should own this retry?"}
               }
             }
           ]
         }},
      "town.delve.feed.getPostThread" =>
        {:ok,
         %{
           "thread" => %{
             "post" => %{
               "uri" => timeline_uri,
               "cid" => "timeline-question-cid",
               "record" => %{"text" => "Which process should own this retry?"}
             },
             "replies" => []
           }
         }}
    })

    Application.put_env(
      :jido_delvetown,
      :decision_result,
      {:ok, %{action: "like", text: nil, topic: "OTP", reason: "Useful question"}}
    )

    assert {:ok, proactive_state} =
             Jido.Exec.run(
               ProactiveParticipationCycle,
               %{mode: "normal"},
               %{agent_state: drained_state}
             )

    assert proactive_state.last_run.status == "simulated"
    assert proactive_state.last_run.action == "like"
    refute_received {:create_record, _collection, _record, _rkey}
  end

  defp run_reactive(state \\ Agent.new!().state) do
    Jido.Exec.run(
      ReactiveParticipationCycle,
      %{mode: "normal"},
      %{agent_state: state}
    )
  end

  defp configure_reactive(notification) do
    uri = notification["uri"]
    cid = notification["cid"]

    Application.put_env(:jido_delvetown, :query_results, %{
      "town.delve.membership.getMembership" => {:ok, %{"status" => "member"}},
      "town.delve.notification.listNotifications" => {:ok, %{"notifications" => [notification]}},
      "town.delve.feed.getPostThread" =>
        {:ok,
         %{
           "thread" => %{
             "post" => %{
               "uri" => uri,
               "cid" => cid,
               "record" => %{"text" => notification["record"]["text"]}
             },
             "replies" => []
           }
         }}
    })
  end

  defp configure_proactive do
    Application.put_env(:jido_delvetown, :query_results, %{
      "town.delve.membership.getMembership" => {:ok, %{"status" => "member"}},
      "town.delve.feed.getTimeline" =>
        {:ok,
         %{
           "feed" => [
             %{
               "post" => %{
                 "uri" => "at://did:plc:member/town.delve.feed.post/question",
                 "cid" => "question-cid",
                 "author" => %{"did" => "did:plc:member"},
                 "record" => %{"text" => "Should this be two processes?"}
               }
             }
           ]
         }}
    })
  end

  defp reply_decision do
    Application.put_env(
      :jido_delvetown,
      :decision_result,
      {:ok,
       %{
         action: "reply",
         text: "Use one process for each independent failure boundary.",
         topic: "OTP",
         reason: "A direct request"
       }}
    )
  end

  defp notification(id, reason, text, suffix \\ "post") do
    %{
      "id" => id,
      "uri" => "at://did:plc:member/town.delve.feed.post/#{suffix}",
      "cid" => "cid-#{suffix}",
      "reason" => reason,
      "isRead" => false,
      "indexedAt" => "2026-10-05T12:00:00Z",
      "author" => %{"did" => "did:plc:member", "handle" => "member.test"},
      "record" => %{
        "text" => text,
        "reply" => %{"root" => %{"uri" => root_uri(), "cid" => "root-cid"}}
      }
    }
  end

  defp root_uri, do: "at://did:plc:root/town.delve.feed.post/root"
end
