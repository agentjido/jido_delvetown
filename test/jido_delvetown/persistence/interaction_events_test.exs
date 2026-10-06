defmodule JidoDelvetown.InteractionEventsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias JidoDelvetown.InteractionEvents
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.InteractionEvent

  setup do
    Repo.delete_all(InteractionEvent)
    :ok
  end

  test "event identity stays stable" do
    assert InteractionEvents.event_key("notification", ["one", nil, 2]) ==
             "notification:cL9NOxXrmo36og1x2HBv5gzZp-OEslEUOZ59Ux17tWs"
  end

  test "duplicate observation updates only a pending event" do
    event_key = "event:duplicate"

    assert {:ok, %InteractionEvent{state: "pending"}} =
             InteractionEvents.observe(%{
               event_key: event_key,
               kind: "reply",
               payload: %{text: "first"}
             })

    assert {:ok, %InteractionEvent{payload: %{"text" => "second"}}} =
             InteractionEvents.observe(%{
               event_key: event_key,
               kind: "mention",
               payload: %{text: "second"}
             })

    assert {:ok, %InteractionEvent{state: "claimed"}} = InteractionEvents.claim(event_key)

    assert {:ok, %InteractionEvent{state: "completed"}} =
             InteractionEvents.finish(event_key, :completed)

    assert {:ok, %InteractionEvent{state: "completed", payload: %{"text" => "second"}}} =
             InteractionEvents.observe(%{
               event_key: event_key,
               kind: "reply",
               payload: %{text: "third"}
             })
  end

  test "claim and finish enforce legal transitions" do
    event_key = "event:transitions"
    assert {:ok, _event} = InteractionEvents.observe(%{event_key: event_key, kind: "reply"})

    assert {:error, {:invalid_transition, "pending", "completed"}} =
             InteractionEvents.finish(event_key, :completed)

    assert {:ok, %InteractionEvent{attempt_count: 1, claimed_at: %DateTime{}}} =
             InteractionEvents.claim(event_key)

    assert {:error, {:not_claimable, "claimed"}} = InteractionEvents.claim(event_key)

    assert {:ok, %InteractionEvent{state: "failed", terminal_at: %DateTime{}}} =
             InteractionEvents.finish(event_key, :failed, %{reason: :timeout})

    assert {:error, {:invalid_transition, "failed", "ignored"}} =
             InteractionEvents.finish(event_key, :ignored)
  end

  test "stale claims return to pending without losing attempt history" do
    event_key = "event:stale"
    old = DateTime.add(DateTime.utc_now(), -10, :minute)

    assert {:ok, _event} = InteractionEvents.observe(%{event_key: event_key, kind: "mention"})
    assert {:ok, _event} = InteractionEvents.claim(event_key)

    Repo.update_all(
      from(event in InteractionEvent, where: event.event_key == ^event_key),
      set: [claimed_at: old]
    )

    assert {:ok, 1} = InteractionEvents.recover_stale_claims(stale_after_ms: 5 * 60 * 1_000)

    assert %InteractionEvent{state: "pending", claimed_at: nil, attempt_count: 1} =
             InteractionEvents.get(event_key)

    assert {:ok, %InteractionEvent{state: "claimed", attempt_count: 2}} =
             InteractionEvents.claim(event_key)
  end

  test "pending queries and terminal checks use the state machine" do
    first = %{event_key: "event:first"}
    second = %{event_key: "event:second"}

    assert {:ok, _event} =
             InteractionEvents.observe(%{event_key: first.event_key, kind: "reply"})

    assert {:ok, _event} =
             InteractionEvents.observe(%{event_key: second.event_key, kind: "mention"})

    assert InteractionEvents.pending?(["reply"])
    assert InteractionEvents.processable?(first.event_key)
    refute InteractionEvents.all_terminal?([first, second])

    assert {:ok, _event} = InteractionEvents.claim(first.event_key)
    assert {:ok, _event} = InteractionEvents.finish(first.event_key, :ignored)
    assert {:ok, _event} = InteractionEvents.claim(second.event_key)
    assert {:ok, _event} = InteractionEvents.finish(second.event_key, :failed)

    refute InteractionEvents.pending?(["reply", "mention"])
    refute InteractionEvents.processable?(first.event_key)
    assert InteractionEvents.processable?("event:unknown")
    assert InteractionEvents.all_terminal?([first, second, first])
  end

  test "manual publication metadata is stored on the event payload" do
    event_key = "event:manual"
    assert {:ok, _event} = InteractionEvents.observe(%{event_key: event_key, kind: "reply"})

    assert {:ok, event} =
             InteractionEvents.record_manual_publication(event_key, %{
               status: "completed",
               uri: "at://did:plc:bot/town.delve.feed.post/reply"
             })

    assert event.payload["manual_publication"] == %{
             "status" => "completed",
             "uri" => "at://did:plc:bot/town.delve.feed.post/reply"
           }

    assert {:error, :not_found} =
             InteractionEvents.record_manual_publication("event:missing", %{status: "completed"})
  end

  test "pruning applies age and bounded retention rules" do
    now = ~U[2026-10-05 12:00:00.000000Z]
    old = ~U[2025-01-01 12:00:00.000000Z]
    recent = DateTime.add(now, -1, :hour)
    latest = DateTime.add(now, -1, :minute)

    insert_terminal_event("event:old", old)
    insert_terminal_event("event:recent", recent)
    insert_terminal_event("event:latest", latest)

    assert {:ok, %{expired: 1, overflow: 1}} =
             InteractionEvents.prune(now: now, retention_days: 90, event_limit: 1)

    assert is_nil(InteractionEvents.get("event:old"))
    assert is_nil(InteractionEvents.get("event:recent"))
    assert %InteractionEvent{} = InteractionEvents.get("event:latest")
  end

  defp insert_terminal_event(event_key, terminal_at) do
    Repo.insert!(%InteractionEvent{
      event_key: event_key,
      kind: "reply",
      state: "completed",
      occurred_at: terminal_at,
      terminal_at: terminal_at,
      payload: %{}
    })
  end
end
