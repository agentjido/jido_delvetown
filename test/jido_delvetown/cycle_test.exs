defmodule JidoDelvetown.CycleTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Agent
  alias JidoDelvetown.ParticipationCycle
  alias JidoDelvetown.Test.{FakeDecision, FakeSession, FakeTransport}

  setup do
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
    old_seen = System.get_env("DELVETOWN_MARK_NOTIFICATIONS_SEEN")

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :decision_module, FakeDecision)
    Application.put_env(:jido_delvetown, :test_owner, self())
    System.put_env("DELVETOWN_WRITE_ENABLED", "false")
    System.put_env("DELVETOWN_MARK_NOTIFICATIONS_SEEN", "false")

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:jido_delvetown, key)
        {key, value} -> Application.put_env(:jido_delvetown, key, value)
      end)

      restore_env("DELVETOWN_WRITE_ENABLED", old_write)
      restore_env("DELVETOWN_MARK_NOTIFICATIONS_SEEN", old_seen)
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

    assert {:ok, state} = Jido.Exec.run(ParticipationCycle, %{mode: "normal"}, context())
    assert state.last_run.status == "proposed"
    assert state.last_run.intent == "answer_direct_request"
    assert state.last_run.action == "reply"
    assert state.last_run.effects == 0
    assert state.notifications.processed[uri].status == "proposed"
    assert state.budget.replies == 0
    refute_received {:create_record, _collection, _record, _rkey}

    assert_received {:decision, "answer_direct_request", payload}
    assert payload.candidate.thread.post.text == "How would you model this in OTP?"
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

    assert {:ok, state} = Jido.Exec.run(ParticipationCycle, %{mode: "review"}, context())
    assert state.last_run.status == "proposed"
    assert state.last_run.intent == "publish_daily_note"
    assert state.last_run.action == "post"
    assert state.budget.posts == 0
    assert state.proactive.last_post_at == ""
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "a question on the timeline selects the discussion intent with a compact thread" do
    uri = "at://did:plc:author/town.delve.feed.post/question"

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

    assert {:ok, state} = Jido.Exec.run(ParticipationCycle, %{mode: "normal"}, context())
    assert state.last_run.intent == "join_useful_discussion"
    assert state.last_run.action == "like"
    assert state.last_run.status == "proposed"
    assert_received {:decision, "join_useful_discussion", payload}
    assert payload.candidate.thread.post.text == "When should one process become two?"
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
