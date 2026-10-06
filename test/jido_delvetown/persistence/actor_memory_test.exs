defmodule JidoDelvetown.ActorMemoryTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.ActorMemory
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{Actor, ActorRelationship}

  setup do
    Repo.delete_all(ActorRelationship)
    Repo.delete_all(Actor)
    :ok
  end

  test "stores contact, welcome, and opt-out state" do
    candidate = %{
      event_key: "member:new",
      reason: "member",
      opt_out?: true,
      author: %{
        did: "did:plc:new-member",
        handle: "new-member.test",
        display_name: "New Member"
      }
    }

    cycle = %{status: "simulated"}

    assert :ok =
             ActorMemory.remember(
               candidate,
               cycle,
               %{action: "welcome"},
               "2026-10-05T12:00:00Z"
             )

    assert %Actor{
             contact_count: 1,
             handle: "new-member.test",
             display_name: "New Member",
             welcome_status: "simulated",
             opted_out: true
           } = ActorMemory.get("did:plc:new-member")

    assert %{
             contact_count: 1,
             welcome_status: "simulated",
             opted_out: true,
             last_interaction_at: "2026-10-05T12:00:00.000000Z"
           } = ActorMemory.context("did:plc:new-member")
  end

  test "keeps one incoming-like entry when a social signal is retried" do
    candidate = %{
      event_key: "like:stable",
      reason: "like",
      indexed_at: "2026-10-05T12:00:00Z",
      author: %{did: "did:plc:liker", handle: "liker.test"}
    }

    cycle = %{candidate: candidate, status: "ignored"}

    assert :ok = ActorMemory.remember_social_signal(candidate, cycle)
    assert :ok = ActorMemory.remember_social_signal(candidate, cycle)

    assert %Actor{contact_count: 0, metadata: metadata} =
             ActorMemory.get("did:plc:liker")

    assert metadata["incoming_likes"] == [
             %{
               "event_key" => "like:stable",
               "observed_at" => "2026-10-05T12:00:00.000000Z"
             }
           ]
  end
end
