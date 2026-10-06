defmodule JidoDelvetown.ManualPublisherTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{InteractionLedger, ManualPublisher, Protocol, Repo}
  alias JidoDelvetown.Storage.{Actor, AuditEvent, Effect, InteractionEvent}
  alias JidoDelvetown.Test.{FakeSession, FakeTransport}

  setup do
    Repo.delete_all(AuditEvent)
    Repo.delete_all(Effect)
    Repo.delete_all(InteractionEvent)
    Repo.delete_all(Actor)

    previous = %{
      session_module: Application.get_env(:jido_delvetown, :session_module),
      transport: Application.get_env(:jido_delvetown, :transport),
      test_owner: Application.get_env(:jido_delvetown, :test_owner),
      query_results: Application.get_env(:jido_delvetown, :query_results),
      create_result: Application.get_env(:jido_delvetown, :create_result),
      get_result: Application.get_env(:jido_delvetown, :get_result)
    }

    old_write = System.get_env("DELVETOWN_WRITE_ENABLED")
    old_manual = System.get_env("DELVETOWN_MANUAL_PUBLISH_ENABLED")
    old_like_limit = System.get_env("DELVETOWN_DAILY_LIKE_LIMIT")

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :test_owner, self())
    Application.put_env(:jido_delvetown, :query_results, %{})
    Application.delete_env(:jido_delvetown, :create_result)
    Application.delete_env(:jido_delvetown, :get_result)
    System.put_env("DELVETOWN_WRITE_ENABLED", "false")
    System.put_env("DELVETOWN_MANUAL_PUBLISH_ENABLED", "true")
    System.put_env("DELVETOWN_DAILY_LIKE_LIMIT", "1")

    on_exit(fn ->
      restore_env(previous)
      restore_system_env("DELVETOWN_WRITE_ENABLED", old_write)
      restore_system_env("DELVETOWN_MANUAL_PUBLISH_ENABLED", old_manual)
      restore_system_env("DELVETOWN_DAILY_LIKE_LIMIT", old_like_limit)
    end)

    :ok
  end

  test "publishes the exact saved reply once while scheduled writes remain off" do
    event = simulated_reply("event:manual-reply")
    Repo.insert!(event)

    assert {:error, :writes_disabled} =
             Protocol.create_record(
               "automatic-write",
               "town.delve.feed.post",
               %{text: "must stay blocked"}
             )

    assert {:ok, publication} = ManualPublisher.publish(event.event_key)
    assert publication.status == "completed"
    assert publication.reused? == false

    assert_received {:create_record, "town.delve.feed.post", record, rkey}
    assert record.text == "Publish this exact saved draft."
    assert record.reply.parent == %{uri: event.record_uri, cid: "parent-cid"}

    assert record.reply.root == %{
             uri: "at://did:plc:root/town.delve.feed.post/root",
             cid: "root-cid"
           }

    assert is_binary(rkey)

    saved = InteractionLedger.event(event.event_key)
    assert saved.payload["manual_publication"]["status"] == "completed"
    assert saved.payload["manual_publication"]["uri"] == publication.uri

    assert {:ok, repeated} = ManualPublisher.publish(event.event_key)
    assert repeated.reused? == true
    assert repeated.uri == publication.uri
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "recovers the reply reference for an older simulated event" do
    event = simulated_reply("event:older-reply")
    payload = Map.delete(event.payload, "publication_target")
    Repo.insert!(%{event | payload: payload})

    Application.put_env(:jido_delvetown, :query_results, %{
      "town.delve.feed.getPostThread" =>
        {:ok,
         %{
           thread: %{
             post: %{
               uri: event.record_uri,
               cid: "recovered-parent-cid",
               author: %{did: event.actor_did},
               record: %{
                 text: "Source post",
                 reply: %{
                   root: %{
                     uri: "at://did:plc:root/town.delve.feed.post/recovered-root",
                     cid: "recovered-root-cid"
                   }
                 }
               }
             }
           }
         }}
    })

    assert {:ok, _publication} = ManualPublisher.publish(event.event_key)

    assert_received {:appview_query, "town.delve.feed.getPostThread", query}
    assert query.uri == event.record_uri
    assert_received {:create_record, "town.delve.feed.post", record, _rkey}
    assert record.reply.parent.cid == "recovered-parent-cid"
    assert record.reply.root.cid == "recovered-root-cid"
  end

  test "rejects a manual publication when its separate permission is off" do
    System.put_env("DELVETOWN_MANUAL_PUBLISH_ENABLED", "false")
    event = simulated_reply("event:disabled")
    Repo.insert!(event)

    assert {:error, :manual_publish_disabled} = ManualPublisher.publish(event.event_key)
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "publishes a simulated welcome with its verified mention and reply target once" do
    did = "did:plc:newmember"
    event = simulated_welcome("event:manual-welcome", did, "new.delve.town")
    Repo.insert!(event)

    Application.put_env(:jido_delvetown, :query_results, %{
      "town.delve.actor.getProfile" => {:ok, %{"did" => did, "handle" => "new.delve.town"}}
    })

    assert {:ok, publication} = ManualPublisher.publish(event.event_key)
    assert publication.reused? == false

    assert_received {:appview_query, "town.delve.actor.getProfile", %{actor: ^did}}
    assert_received {:create_record, "town.delve.feed.post", record, _rkey}
    assert record["$type"] == "town.delve.feed.post"
    assert record.text == "@new.delve.town Welcome to the OTP discussions."
    assert [facet] = record.facets
    assert facet.index == %{byte_start: 0, byte_end: 15}
    assert facet.features == [%{"$type" => "town.delve.richtext.facet#mention", did: did}]
    assert record.reply.parent.uri == event.record_uri

    effect_key = Protocol.effect_key("welcome", [did])
    assert %Effect{status: "completed", operation_key: ^effect_key} = Repo.get(Effect, effect_key)

    assert {:ok, repeated} = ManualPublisher.publish(event.event_key)
    assert repeated.reused? == true
    assert repeated.uri == publication.uri
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "does not manually publish a welcome when the saved handle resolves to another DID" do
    did = "did:plc:newmember"
    event = simulated_welcome("event:unsafe-welcome", did, "new.delve.town")
    Repo.insert!(event)

    Application.put_env(:jido_delvetown, :query_results, %{
      "town.delve.actor.getProfile" =>
        {:ok, %{"did" => "did:plc:other", "handle" => "new.delve.town"}}
    })

    assert {:error, :welcome_identity_unresolved} = ManualPublisher.publish(event.event_key)
    refute_received {:create_record, _collection, _record, _rkey}
    assert Repo.get(Effect, Protocol.effect_key("welcome", [did])) == nil
  end

  test "publishes the exact saved like once after a live eligibility check" do
    event = simulated_like("event:manual-like")
    Repo.insert!(event)
    configure_like_thread(event)

    assert {:error, :writes_disabled} =
             Protocol.create_record(
               "automatic-like",
               "town.delve.feed.like",
               %{subject: %{uri: event.record_uri, cid: "post-cid"}}
             )

    assert {:ok, publication} = ManualPublisher.publish(event.event_key)
    assert publication.status == "completed"
    assert publication.reused? == false
    assert publication.target_uri == event.record_uri
    assert publication.target_cid == "post-cid"

    assert_received {:appview_query, "town.delve.feed.getPostThread", %{uri: uri}}
    assert uri == event.record_uri

    assert_received {:create_record, "town.delve.feed.like", record, rkey}
    assert record.subject == %{uri: event.record_uri, cid: "post-cid"}
    assert is_binary(rkey)

    effect_key = Protocol.effect_key("like", [event.record_uri])
    assert %Effect{status: "completed", operation_key: ^effect_key} = Repo.get(Effect, effect_key)

    saved = InteractionLedger.event(event.event_key)
    assert saved.payload["manual_publication"]["status"] == "completed"
    assert saved.payload["manual_publication"]["target_uri"] == event.record_uri
    assert saved.payload["manual_publication"]["target_cid"] == "post-cid"

    start_of_day =
      DateTime.utc_now()
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    assert InteractionLedger.outreach_count("like", start_of_day) == 1

    assert {:ok, repeated} = ManualPublisher.publish(event.event_key)
    assert repeated.reused? == true
    assert repeated.uri == publication.uri
    assert_received {:appview_query, "town.delve.feed.getPostThread", %{uri: ^uri}}
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "rejects a changed or stale like target without creating an effect" do
    changed = simulated_like("event:changed-like")
    Repo.insert!(changed)
    configure_like_thread(changed, cid: "changed-cid")

    assert {:error, :like_target_changed} = ManualPublisher.publish(changed.event_key)
    refute_received {:create_record, _collection, _record, _rkey}
    assert Repo.get(Effect, Protocol.effect_key("like", [changed.record_uri])) == nil

    stale = simulated_like("event:stale-like", "stale")
    Repo.insert!(stale)

    configure_like_thread(stale,
      indexed_at: DateTime.utc_now() |> DateTime.add(-72, :hour) |> DateTime.to_iso8601()
    )

    assert {:error, {:like_not_eligible, "stale_candidate"}} =
             ManualPublisher.publish(stale.event_key)

    refute_received {:create_record, _collection, _record, _rkey}
    assert Repo.get(Effect, Protocol.effect_key("like", [stale.record_uri])) == nil
  end

  test "does not duplicate a remote like without a matching local effect" do
    event = simulated_like("event:remote-like")
    Repo.insert!(event)

    configure_like_thread(event,
      viewer: %{like: "at://did:plc:bot/town.delve.feed.like/existing"}
    )

    assert {:error, {:like_not_eligible, "already_liked"}} =
             ManualPublisher.publish(event.event_key)

    refute_received {:create_record, _collection, _record, _rkey}
    assert Repo.get(Effect, Protocol.effect_key("like", [event.record_uri])) == nil
  end

  test "reconciles an uncertain matching like effect without a second create" do
    event = simulated_like("event:reconciled-like")
    Repo.insert!(event)
    configure_like_thread(event, viewer: %{like: "at://did:plc:bot/town.delve.feed.like/fixed"})

    effect_key = Protocol.effect_key("like", [event.record_uri])
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.insert!(%Effect{
      operation_key: effect_key,
      kind: "like",
      collection: "town.delve.feed.like",
      subject_key: event.record_uri,
      rkey: "fixed",
      status: "uncertain",
      attempt_count: 1,
      reserved_at: now
    })

    Application.put_env(
      :jido_delvetown,
      :get_result,
      {:ok, %{uri: "at://did:plc:bot/town.delve.feed.like/fixed", cid: "reconciled-like-cid"}}
    )

    assert {:ok, publication} = ManualPublisher.publish(event.event_key)
    assert publication.reconciled? == true
    assert publication.reused? == false
    assert_received {:get_record, "town.delve.feed.like", "fixed"}
    refute_received {:create_record, _collection, _record, _rkey}
    assert Repo.get!(Effect, effect_key).status == "completed"
  end

  defp simulated_reply(event_key) do
    now = ~U[2026-10-05 12:00:00.000000Z]

    %InteractionEvent{
      event_key: event_key,
      kind: "reply",
      actor_did: "did:plc:member",
      record_uri: "at://did:plc:member/town.delve.feed.post/source",
      source_id: "notification-1",
      occurred_at: now,
      state: "completed",
      attempt_count: 1,
      payload: %{
        "action" => "reply",
        "cycle_status" => "simulated",
        "text" => "Publish this exact saved draft.",
        "publication_target" => %{
          "uri" => "at://did:plc:member/town.delve.feed.post/source",
          "cid" => "parent-cid",
          "root" => %{
            "uri" => "at://did:plc:root/town.delve.feed.post/root",
            "cid" => "root-cid"
          }
        }
      },
      terminal_at: now
    }
  end

  defp simulated_welcome(event_key, did, handle) do
    now = ~U[2026-10-05 12:00:00.000000Z]
    uri = "at://#{did}/town.delve.feed.post/3mx6intro"

    %InteractionEvent{
      event_key: event_key,
      kind: "new_member",
      actor_did: did,
      record_uri: uri,
      source_id: did,
      occurred_at: now,
      state: "completed",
      attempt_count: 1,
      payload: %{
        "action" => "welcome",
        "cycle_status" => "simulated",
        "text" => "@#{handle} Welcome to the OTP discussions.",
        "publication_actor" => %{"did" => did, "handle" => handle},
        "publication_target" => %{
          "uri" => uri,
          "cid" => "bafyreintro",
          "root" => %{"uri" => uri, "cid" => "bafyreintro"}
        }
      },
      terminal_at: now
    }
  end

  defp simulated_like(event_key, rkey \\ "target") do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    uri = "at://did:plc:author/town.delve.feed.post/#{rkey}"

    %InteractionEvent{
      event_key: event_key,
      kind: "proactive",
      actor_did: "did:plc:author",
      record_uri: uri,
      source_id: uri,
      occurred_at: now,
      state: "completed",
      attempt_count: 1,
      payload: %{
        "action" => "like",
        "cycle_status" => "simulated",
        "publication_target" => %{"uri" => uri, "cid" => "post-cid"},
        "like_review" => %{
          "author" => %{"did" => "did:plc:author", "handle" => "author.test"},
          "post_text" => "How should this process failure be isolated?",
          "selected_at" => DateTime.to_iso8601(now)
        }
      },
      terminal_at: now
    }
  end

  defp configure_like_thread(event, opts \\ []) do
    cid = Keyword.get(opts, :cid, "post-cid")
    viewer = Keyword.get(opts, :viewer, %{})
    indexed_at = Keyword.get(opts, :indexed_at, Protocol.now())

    Application.put_env(:jido_delvetown, :query_results, %{
      "town.delve.feed.getPostThread" =>
        {:ok,
         %{
           thread: %{
             post: %{
               uri: event.record_uri,
               cid: cid,
               indexed_at: indexed_at,
               author: %{
                 did: event.actor_did,
                 handle: "author.test",
                 viewer: %{blocked_by: false}
               },
               viewer: viewer,
               labels: [],
               record: %{text: "How should this process failure be isolated?"}
             }
           }
         }}
    })
  end

  defp restore_env(values) do
    Enum.each(values, fn
      {key, nil} -> Application.delete_env(:jido_delvetown, key)
      {key, value} -> Application.put_env(:jido_delvetown, key, value)
    end)
  end

  defp restore_system_env(name, nil), do: System.delete_env(name)
  defp restore_system_env(name, value), do: System.put_env(name, value)
end
