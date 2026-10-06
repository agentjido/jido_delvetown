defmodule JidoDelvetown.CycleTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Agent

  alias JidoDelvetown.{
    ProactiveParticipationCycle,
    ReactiveParticipationCycle,
    Repo,
    ScanProgress,
    Store
  }

  alias JidoDelvetown.Storage.{Actor, Conversation, InteractionEvent, ScanState}
  alias JidoDelvetown.Test.{FakeDecision, FakeSession, FakeTransport}

  setup do
    Enum.each([ScanState, InteractionEvent, Conversation, Actor], &Repo.delete_all/1)

    keys = [
      :session_module,
      :transport,
      :decision_module,
      :query_results,
      :decision_result,
      :test_owner
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:jido_delvetown, &1)})
    old_write = System.get_env("DELVETOWN_WRITE_ENABLED")
    old_dry_run = System.get_env("DELVETOWN_DRY_RUN_MARK_ACTIONED")
    old_seen = System.get_env("DELVETOWN_MARK_NOTIFICATIONS_SEEN")
    old_reply_limit = System.get_env("DELVETOWN_DAILY_REPLY_LIMIT")
    old_like_limit = System.get_env("DELVETOWN_DAILY_LIKE_LIMIT")
    old_like_cooldown = System.get_env("DELVETOWN_LIKE_ACTOR_COOLDOWN_HOURS")
    old_like_max_age = System.get_env("DELVETOWN_LIKE_CANDIDATE_MAX_AGE_HOURS")

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :decision_module, FakeDecision)
    Application.put_env(:jido_delvetown, :test_owner, self())
    System.put_env("DELVETOWN_WRITE_ENABLED", "false")
    System.put_env("DELVETOWN_DRY_RUN_MARK_ACTIONED", "false")
    System.put_env("DELVETOWN_MARK_NOTIFICATIONS_SEEN", "false")
    System.put_env("DELVETOWN_DAILY_REPLY_LIMIT", "3")
    System.put_env("DELVETOWN_DAILY_LIKE_LIMIT", "5")
    System.put_env("DELVETOWN_LIKE_ACTOR_COOLDOWN_HOURS", "24")
    System.put_env("DELVETOWN_LIKE_CANDIDATE_MAX_AGE_HOURS", "48")

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:jido_delvetown, key)
        {key, value} -> Application.put_env(:jido_delvetown, key, value)
      end)

      restore_env("DELVETOWN_WRITE_ENABLED", old_write)
      restore_env("DELVETOWN_DRY_RUN_MARK_ACTIONED", old_dry_run)
      restore_env("DELVETOWN_MARK_NOTIFICATIONS_SEEN", old_seen)
      restore_env("DELVETOWN_DAILY_REPLY_LIMIT", old_reply_limit)
      restore_env("DELVETOWN_DAILY_LIKE_LIMIT", old_like_limit)
      restore_env("DELVETOWN_LIKE_ACTOR_COOLDOWN_HOURS", old_like_cooldown)
      restore_env("DELVETOWN_LIKE_CANDIDATE_MAX_AGE_HOURS", old_like_max_age)
    end)

    :ok
  end

  test "an unread reply selects the reactive intent and remains a dry-run proposal" do
    uri = "at://did:plc:author/town.delve.feed.post/reply"

    configure_reads(%{
      "town.delve.notification.listNotifications" =>
        {:ok,
         %{
           "notifications" => [
             %{
               "id" => "event-like-priority",
               "uri" => "at://did:plc:liker/town.delve.feed.like/priority",
               "cid" => "like-cid",
               "reason" => "like",
               "reasonSubject" => "at://did:plc:agent/town.delve.feed.post/liked",
               "isRead" => false,
               "indexedAt" => "2026-10-05T11:58:00Z",
               "author" => %{"did" => "did:plc:liker", "handle" => "liker.test"},
               "record" => %{
                 "subject" => %{
                   "uri" => "at://did:plc:agent/town.delve.feed.post/liked",
                   "cid" => "liked-post-cid"
                 }
               }
             },
             %{
               "uri" => uri,
               "cid" => "reply-cid",
               "reason" => "reply",
               "isRead" => false,
               "author" => %{"did" => "did:plc:author", "handle" => "author.test"},
               "record" => %{
                 "text" => "How would you model this in OTP?",
                 "reply" => %{
                   "root" => %{"uri" => "at://did:plc:root/post/root", "cid" => "root-cid"}
                 }
               }
             }
           ]
         }},
      "town.delve.feed.getPostThread" =>
        {:ok,
         %{
           "thread" => %{
             "post" => %{
               "uri" => uri,
               "cid" => "reply-cid",
               "record" => %{"text" => "How would you model this in OTP?"}
             },
             "replies" => []
           }
         }}
    })

    Application.put_env(
      :jido_delvetown,
      :decision_result,
      {:ok,
       %{
         action: "reply",
         text: "Use one supervised process for each independent failure boundary.",
         topic: "OTP",
         reason: "A direct technical question"
       }}
    )

    assert {:ok, state} =
             Jido.Exec.run(ReactiveParticipationCycle, %{mode: "normal"}, context())

    assert state.last_run.kind == "reactive"
    assert state.last_run.status == "proposed"
    assert state.last_run.intent == "answer_direct_request"
    assert state.last_run.action == "reply"
    assert state.last_run.effects == 0
    assert is_integer(state.last_run.selection.score)
    assert state.last_run.selection.reason =~ "direct scored"
    assert state.notifications.processed[uri].status == "proposed"
    assert state.notifications.processed["event-like-priority"].status == "ignored"
    assert state.budget.replies == 0
    assert Repo.get_by!(InteractionEvent, record_uri: uri).state == "pending"

    assert %InteractionEvent{state: "ignored", kind: "like"} =
             Repo.get!(InteractionEvent, "notification:event-like-priority")

    refute_received {:create_record, _collection, _record, _rkey}

    assert_received {:decision, "answer_direct_request", payload}
    assert payload.candidate.thread.post.text == "How would you model this in OTP?"

    decision_event = Enum.find(Store.recent_events(Store, 10), &(&1.type == :decision))
    assert decision_event.data.selection.reason == state.last_run.selection.reason
  end

  test "an incoming like becomes one terminal social signal without a reply" do
    like_uri = "at://did:plc:liker/town.delve.feed.like/one"
    target_uri = "at://did:plc:agent/town.delve.feed.post/liked"

    configure_reads(%{
      "town.delve.notification.listNotifications" =>
        {:ok,
         %{
           "notifications" => [
             %{
               "uri" => like_uri,
               "cid" => "like-cid",
               "reason" => "liked",
               "reasonSubject" => target_uri,
               "isRead" => false,
               "indexedAt" => "2026-10-05T12:00:00Z",
               "author" => %{
                 "did" => "did:plc:liker",
                 "handle" => "liker.test",
                 "displayName" => "Liker"
               },
               "record" => %{
                 "subject" => %{"uri" => target_uri, "cid" => "target-cid"}
               }
             }
           ]
         }}
    })

    assert {:ok, first_state} =
             Jido.Exec.run(ReactiveParticipationCycle, %{mode: "normal"}, context())

    assert first_state.last_run.status == "skipped"
    assert first_state.last_run.intent == "skip"
    assert first_state.last_run.action == "skip"
    assert first_state.notifications.processed[like_uri].status == "ignored"

    event = Repo.get_by!(InteractionEvent, source_id: like_uri)
    assert event.kind == "like"
    assert event.state == "ignored"
    assert event.attempt_count == 1
    assert event.record_uri == target_uri
    assert event.payload["target_cid"] == "target-cid"
    assert event.payload["notification_cid"] == "like-cid"

    actor = Repo.get!(Actor, "did:plc:liker")
    assert actor.handle == "liker.test"
    assert actor.contact_count == 0
    assert actor.last_interaction_at == nil

    assert actor.metadata["incoming_likes"] == [
             %{
               "event_key" => event.event_key,
               "observed_at" => "2026-10-05T12:00:00.000000Z"
             }
           ]

    assert {:ok, repeated_state} =
             Jido.Exec.run(ReactiveParticipationCycle, %{mode: "normal"}, context())

    assert repeated_state.last_run.status == "skipped"
    assert Repo.get!(InteractionEvent, event.event_key).attempt_count == 1

    assert Repo.get!(Actor, "did:plc:liker").metadata["incoming_likes"] ==
             actor.metadata["incoming_likes"]

    refute_received {:decision, _intent, _payload}
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "a dry-run action can advance local memory without a protocol write" do
    System.put_env("DELVETOWN_DRY_RUN_MARK_ACTIONED", "true")
    uri = "at://did:plc:simulated/town.delve.feed.post/reply"
    root_uri = "at://did:plc:root/town.delve.feed.post/simulated"

    configure_reads(%{
      "town.delve.notification.listNotifications" =>
        {:ok,
         %{
           "notifications" => [
             %{
               "uri" => uri,
               "cid" => "reply-cid",
               "reason" => "reply",
               "isRead" => false,
               "author" => %{
                 "did" => "did:plc:simulated",
                 "handle" => "simulated.test"
               },
               "record" => %{
                 "text" => "How would you isolate this process?",
                 "reply" => %{
                   "root" => %{"uri" => root_uri, "cid" => "root-cid"}
                 }
               }
             }
           ]
         }},
      "town.delve.feed.getPostThread" =>
        {:ok,
         %{
           "thread" => %{
             "post" => %{
               "uri" => uri,
               "cid" => "reply-cid",
               "record" => %{"text" => "How would you isolate this process?"}
             },
             "replies" => []
           }
         }}
    })

    Application.put_env(
      :jido_delvetown,
      :decision_result,
      {:ok,
       %{
         action: "reply",
         text: "Give each independent failure one supervised process.",
         topic: "OTP",
         reason: "A direct technical question"
       }}
    )

    assert {:ok, state} =
             Jido.Exec.run(ReactiveParticipationCycle, %{mode: "normal"}, context())

    assert state.last_run.status == "simulated"
    assert state.last_run.effects == 0
    assert state.notifications.processed[uri].status == "simulated"
    assert state.budget.replies == 1
    event = Repo.get_by!(InteractionEvent, record_uri: uri)
    assert event.state == "completed"
    assert event.payload["text"] == "Give each independent failure one supervised process."
    assert event.payload["topic"] == "OTP"
    assert event.payload["model_reason"] == "A direct technical question"
    assert Repo.get!(Actor, "did:plc:simulated").contact_count == 1
    assert Repo.get!(Conversation, root_uri).turn_count == 1
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "a quiet timeline selects one daily note and keeps the daily budget unchanged in review" do
    configure_reads(%{
      "town.delve.notification.listNotifications" => {:ok, %{"notifications" => []}},
      "town.delve.feed.getTimeline" =>
        {:ok,
         %{
           "feed" => [
             %{
               "post" => %{
                 "uri" => "at://did:plc:author/town.delve.feed.post/one",
                 "cid" => "cid-one",
                 "author" => %{"did" => "did:plc:author", "handle" => "author.test"},
                 "record" => %{"text" => "A calm note without a question"}
               }
             }
           ]
         }}
    })

    Application.put_env(
      :jido_delvetown,
      :decision_result,
      {:ok,
       %{
         action: "post",
         text:
           "Small OTP boundaries make failure easier to understand. Which boundary helped you most?",
         topic: "OTP boundaries",
         reason: "Daily field note"
       }}
    )

    assert {:ok, state} =
             Jido.Exec.run(ProactiveParticipationCycle, %{mode: "review"}, context())

    assert state.last_run.kind == "proactive"
    assert state.last_run.status == "proposed"
    assert state.last_run.intent == "publish_daily_note"
    assert state.last_run.action == "post"
    assert state.budget.posts == 0
    assert state.proactive.last_post_at == ""
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "a question on the timeline selects the discussion intent with a compact thread" do
    uri = "at://did:plc:author/town.delve.feed.post/question"
    indexed_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    configure_reads(%{
      "town.delve.notification.listNotifications" => {:ok, %{"notifications" => []}},
      "town.delve.feed.getTimeline" =>
        {:ok,
         %{
           "feed" => [
             %{
               "post" => %{
                 "uri" => uri,
                 "cid" => "question-cid",
                 "indexedAt" => indexed_at,
                 "author" => %{"did" => "did:plc:author", "handle" => "author.test"},
                 "record" => %{"text" => "When should one process become two?"}
               }
             }
           ]
         }},
      "town.delve.feed.getPostThread" =>
        {:ok,
         %{
           "thread" => %{
             "post" => %{
               "uri" => uri,
               "cid" => "question-cid",
               "record" => %{"text" => "When should one process become two?"}
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

    agent_state =
      Agent.new!().state
      |> Map.put(:budget, %{
        date: Date.utc_today() |> Date.to_iso8601(),
        replies: 3,
        likes: 0,
        posts: 0
      })

    assert {:ok, state} =
             Jido.Exec.run(ProactiveParticipationCycle, %{mode: "normal"}, %{
               agent_state: agent_state
             })

    assert state.last_run.kind == "proactive"
    assert state.last_run.intent == "join_useful_discussion"
    assert state.last_run.action == "like"
    assert state.last_run.status == "proposed"
    assert state.budget.likes == 0
    assert state.budget.replies == 3
    assert_received {:decision, "join_useful_discussion", payload}
    assert payload.allowed_actions == ["like", "skip"]
    assert payload.candidate.thread.post.text == "When should one process become two?"
  end

  test "a simulated outgoing like consumes only the like budget and is not selected twice" do
    System.put_env("DELVETOWN_DRY_RUN_MARK_ACTIONED", "true")
    uri = "at://did:plc:author/town.delve.feed.post/like-once"
    indexed_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    configure_reads(%{
      "town.delve.feed.getTimeline" =>
        {:ok,
         %{
           "feed" => [
             %{
               "post" => %{
                 "uri" => uri,
                 "cid" => "like-once-cid",
                 "indexedAt" => indexed_at,
                 "author" => %{"did" => "did:plc:author", "handle" => "author.test"},
                 "viewer" => %{},
                 "labels" => [],
                 "record" => %{"text" => "Which OTP boundary should own this failure?"}
               }
             }
           ]
         }},
      "town.delve.feed.getPostThread" =>
        {:ok,
         %{
           "thread" => %{
             "post" => %{
               "uri" => uri,
               "cid" => "like-once-cid",
               "record" => %{"text" => "Which OTP boundary should own this failure?"}
             },
             "replies" => []
           }
         }}
    })

    Application.put_env(
      :jido_delvetown,
      :decision_result,
      {:ok, %{action: "like", text: nil, topic: "OTP", reason: "Useful OTP discussion"}}
    )

    assert {:ok, state} =
             Jido.Exec.run(ProactiveParticipationCycle, %{mode: "normal"}, context())

    assert state.last_run.status == "simulated"
    assert state.last_run.action == "like"
    assert state.budget.likes == 1
    assert state.budget.replies == 0
    assert state.budget.posts == 0
    assert_received {:decision, "join_useful_discussion", _payload}
    refute_received {:create_record, _collection, _record, _rkey}

    assert {:ok, repeated} =
             Jido.Exec.run(ProactiveParticipationCycle, %{mode: "normal"}, %{agent_state: state})

    assert repeated.last_run.status == "skipped"
    assert repeated.last_run.proposal.reason == "duplicate_candidate"
    assert repeated.budget.likes == 1
    refute_received {:decision, _intent, _payload}
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "a reactive cycle restores and advances one bounded notification page" do
    assert {:ok, _scan} = ScanProgress.put_cursor("notifications", "cursor-1")

    configure_reads(%{
      "town.delve.notification.listNotifications" =>
        {:ok, %{"cursor" => "cursor-2", "notifications" => []}}
    })

    assert {:ok, state} =
             Jido.Exec.run(ReactiveParticipationCycle, %{mode: "normal"}, context())

    assert state.last_run.status == "skipped"

    assert_received {:appview_query, "town.delve.notification.listNotifications",
                     %{cursor: "cursor-1", limit: 20}}

    refute_received {:appview_query, "town.delve.notification.listNotifications", _params}
    assert ScanProgress.get("notifications").cursor == "cursor-2"
  end

  test "an overlapping reactive trigger stops before protocol reads" do
    assert {:ok, scan} = ScanProgress.claim("notifications")

    assert {:ok, state} =
             Jido.Exec.run(ReactiveParticipationCycle, %{mode: "normal"}, context())

    assert state.last_run.status == "skipped"
    assert state.last_run.summary =~ "skipped"
    refute_received {:appview_query, _method, _params}

    assert {:ok, _scan} = ScanProgress.release("notifications", scan.token)
  end

  test "a skipped follow becomes terminal before the notification batch is marked as seen" do
    System.put_env("DELVETOWN_MARK_NOTIFICATIONS_SEEN", "true")

    configure_reads(%{
      "town.delve.notification.listNotifications" =>
        {:ok,
         %{
           "notifications" => [
             %{
               "id" => "event-follow",
               "reason" => "follow",
               "isRead" => false,
               "indexedAt" => "2026-10-05T12:00:00Z",
               "author" => %{"did" => "did:plc:new-follower"}
             }
           ]
         }}
    })

    assert {:ok, state} =
             Jido.Exec.run(ReactiveParticipationCycle, %{mode: "normal"}, context())

    assert state.last_run.status == "skipped"
    assert state.notifications.processed["event-follow"].status == "skipped"

    assert %InteractionEvent{state: "ignored"} =
             Repo.get(InteractionEvent, "notification:event-follow")

    assert_received {:decision, "respond_to_new_follow", _payload}
    assert_received {:appview_procedure, "town.delve.notification.updateSeen", _body}
  end

  defp context do
    %{agent_state: Agent.new!().state}
  end

  defp configure_reads(overrides) do
    Application.put_env(
      :jido_delvetown,
      :query_results,
      Map.put(overrides, "town.delve.membership.getMembership", {:ok, %{"status" => "member"}})
    )
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
