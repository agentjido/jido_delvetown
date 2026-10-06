defmodule JidoDelvetown.ManualPublisherTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{InteractionLedger, ManualPublisher, Protocol, Repo}
  alias JidoDelvetown.Storage.{AuditEvent, Effect, InteractionEvent}
  alias JidoDelvetown.Test.{FakeSession, FakeTransport}

  setup do
    Repo.delete_all(AuditEvent)
    Repo.delete_all(Effect)
    Repo.delete_all(InteractionEvent)

    previous = %{
      session_module: Application.get_env(:jido_delvetown, :session_module),
      transport: Application.get_env(:jido_delvetown, :transport),
      test_owner: Application.get_env(:jido_delvetown, :test_owner),
      query_results: Application.get_env(:jido_delvetown, :query_results)
    }

    old_write = System.get_env("DELVETOWN_WRITE_ENABLED")
    old_manual = System.get_env("DELVETOWN_MANUAL_PUBLISH_ENABLED")

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :test_owner, self())
    System.put_env("DELVETOWN_WRITE_ENABLED", "false")
    System.put_env("DELVETOWN_MANUAL_PUBLISH_ENABLED", "true")

    on_exit(fn ->
      restore_env(previous)
      restore_system_env("DELVETOWN_WRITE_ENABLED", old_write)
      restore_system_env("DELVETOWN_MANUAL_PUBLISH_ENABLED", old_manual)
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

  defp restore_env(values) do
    Enum.each(values, fn
      {key, nil} -> Application.delete_env(:jido_delvetown, key)
      {key, value} -> Application.put_env(:jido_delvetown, key, value)
    end)
  end

  defp restore_system_env(name, nil), do: System.delete_env(name)
  defp restore_system_env(name, value), do: System.put_env(name, value)
end
