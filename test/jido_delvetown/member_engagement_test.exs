defmodule JidoDelvetown.MemberEngagementTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{
    Agent,
    InteractionLedger,
    MemberDiscoveryCycle,
    Protocol,
    Repo,
    ScanProgress
  }

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
      :test_owner
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:jido_delvetown, &1)})
    old_write = System.get_env("DELVETOWN_WRITE_ENABLED")
    old_dry_run = System.get_env("DELVETOWN_DRY_RUN_MARK_ACTIONED")
    old_limit = System.get_env("DELVETOWN_DAILY_WELCOME_LIMIT")
    old_age = System.get_env("DELVETOWN_MEMBER_MAX_AGE_HOURS")

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :decision_module, FakeDecision)
    Application.put_env(:jido_delvetown, :test_owner, self())
    System.put_env("DELVETOWN_WRITE_ENABLED", "true")
    System.put_env("DELVETOWN_DRY_RUN_MARK_ACTIONED", "false")
    System.put_env("DELVETOWN_DAILY_WELCOME_LIMIT", "2")
    System.put_env("DELVETOWN_MEMBER_MAX_AGE_HOURS", "24")

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:jido_delvetown, key)
        {key, value} -> Application.put_env(:jido_delvetown, key, value)
      end)

      restore_env("DELVETOWN_WRITE_ENABLED", old_write)
      restore_env("DELVETOWN_DRY_RUN_MARK_ACTIONED", old_dry_run)
      restore_env("DELVETOWN_DAILY_WELCOME_LIMIT", old_limit)
      restore_env("DELVETOWN_MEMBER_MAX_AGE_HOURS", old_age)
    end)

    :ok
  end

  test "discovers and welcomes a recent member who does not follow the agent" do
    joined_at = recent_time(-10)
    configure_members([member("did:plc:new-member", joined_at)])
    welcome_decision("A failure-boundary thread is a useful first stop in town.")

    assert {:ok, state} = run()
    assert state.last_run.kind == "members"
    assert state.last_run.intent == "welcome_new_member"
    assert state.last_run.status == "acted"

    assert_received {:appview_query, "town.delve.actor.searchActors", %{limit: 20}}
    refute_received {:appview_query, "town.delve.notification.listNotifications", _params}
    assert_received {:decision, "welcome_new_member", payload}
    assert payload.candidate.text =~ "OTP"

    assert_received {:appview_query, "town.delve.actor.getProfile",
                     %{actor: "did:plc:new-member"}}

    assert_received {:create_record, "town.delve.feed.post", record, _rkey}
    assert record["$type"] == "town.delve.feed.post"
    assert record.text =~ "@new-member.delve.town"
    assert [facet] = record.facets
    assert facet["$type"] == "town.delve.richtext.facet"
    assert facet.index == %{byte_start: 0, byte_end: 22}

    assert facet.features == [
             %{
               "$type" => "town.delve.richtext.facet#mention",
               did: "did:plc:new-member"
             }
           ]

    refute Map.has_key?(record, :reply)

    event_key = InteractionLedger.event_key("new_member", ["did:plc:new-member"])
    assert %InteractionEvent{state: "completed"} = Repo.get(InteractionEvent, event_key)

    effect_key = Protocol.effect_key("welcome", ["did:plc:new-member"])
    assert %Effect{status: "completed"} = Repo.get(Effect, effect_key)
    assert Repo.get!(Actor, "did:plc:new-member").welcome_status == "completed"
    assert ScanProgress.get("members").cursor == "#{joined_at}|did:plc:new-member"
  end

  test "a repeated and overlapping discovery does not repeat a welcome after restart" do
    joined_at = recent_time(-10)
    actor = member("did:plc:overlap", joined_at)
    configure_members([actor])
    welcome_decision("Welcome. The supervision discussions may fit your profile.")

    assert {:ok, _state} = run()
    assert_received {:decision, "welcome_new_member", _payload}
    assert_received {:create_record, "town.delve.feed.post", _record, _rkey}

    assert {:ok, _scan} = ScanProgress.put_cursor("members", nil)
    configure_members([actor])

    assert {:ok, state} = run(Agent.new!().state)
    assert state.last_run.status == "skipped"
    refute_received {:decision, _intent, _payload}
    refute_received {:create_record, "town.delve.feed.post", _record, _rkey}

    effect_key = Protocol.effect_key("welcome", ["did:plc:overlap"])
    assert Repo.get!(Effect, effect_key).attempt_count == 1
  end

  test "an overlapping page selects the next pending member in stable order" do
    first_time = recent_time(-20)
    second_time = recent_time(-10)
    first = member("did:plc:first", first_time)
    second = member("did:plc:second", second_time)
    welcome_decision("Welcome. Your profile points to a useful systems discussion.")

    configure_members([first])
    assert {:ok, first_state} = run()
    assert_received {:decision, "welcome_new_member", first_payload}
    assert first_payload.candidate.id == "did:plc:first"

    configure_members([second, first])
    assert {:ok, _second_state} = run(first_state)
    assert_received {:decision, "welcome_new_member", second_payload}
    assert second_payload.candidate.id == "did:plc:second"

    assert ScanProgress.get("members").cursor == "#{second_time}|did:plc:second"
    assert Repo.aggregate(InteractionEvent, :count, :event_key) == 2
  end

  test "a member with prior contact is not welcomed" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Actor{
      did: "did:plc:known",
      handle: "known.delve.town",
      profile: %{},
      first_seen_at: now,
      last_seen_at: now,
      last_interaction_at: now,
      contact_count: 1,
      metadata: %{}
    }
    |> Repo.insert!()

    configure_members([member("did:plc:known", recent_time(-10))])

    assert {:ok, state} = run()
    assert state.last_run.status == "skipped"
    assert state.last_run.proposal.reason == "member_already_contacted"
    refute_received {:decision, _intent, _payload}
  end

  test "an old member is observed but not contacted" do
    configure_members([member("did:plc:old", recent_time(-48 * 60))])

    assert {:ok, state} = run()
    assert state.last_run.status == "skipped"
    assert state.last_run.proposal.reason == "member_too_old"

    event_key = InteractionLedger.event_key("new_member", ["did:plc:old"])
    assert Repo.get!(InteractionEvent, event_key).state == "ignored"
    refute_received {:decision, _intent, _payload}
  end

  test "the daily welcome limit leaves the event pending" do
    System.put_env("DELVETOWN_DAILY_WELCOME_LIMIT", "0")
    configure_members([member("did:plc:later", recent_time(-10))])

    assert {:ok, state} = run()
    assert state.last_run.proposal.reason == "welcome_budget_exhausted"

    event_key = InteractionLedger.event_key("new_member", ["did:plc:later"])
    assert Repo.get!(InteractionEvent, event_key).state == "pending"
    refute_received {:decision, _intent, _payload}
  end

  test "replies to a safe introduction post from the new member" do
    did = "did:plc:intro-member"
    joined_at = recent_time(-10)
    configure_members([member(did, joined_at)], introduction_feed(did))
    welcome_decision("The OTP discussions may be useful to you.")

    assert {:ok, state} = run()
    assert state.last_run.status == "acted"
    assert state.last_run.reads == 4

    uri = "at://#{did}/town.delve.feed.post/3mx6intro"

    assert_received {:create_record, "town.delve.feed.post", record, _rkey}
    assert record.text =~ "@intro-member.delve.town"

    assert record.reply == %{
             parent: %{uri: uri, cid: "bafyreintro"},
             root: %{uri: uri, cid: "bafyreintro"}
           }

    event_key = InteractionLedger.event_key("new_member", [did])
    event = Repo.get!(InteractionEvent, event_key)
    assert event.record_uri == uri
    assert event.payload["publication_target"]["uri"] == uri
  end

  test "does not publish when the handle does not resolve to the member DID" do
    did = "did:plc:unresolved"
    joined_at = recent_time(-10)

    configure_members([member(did, joined_at)], [], %{
      "did" => "did:plc:different",
      "handle" => "unresolved.delve.town"
    })

    welcome_decision("Welcome to the systems discussions.")

    assert {:ok, state} = run()
    assert state.last_run.status == "failed"
    assert state.last_run.errors == ["welcome_identity_unresolved"]
    refute_received {:create_record, _collection, _record, _rkey}

    effect_key = Protocol.effect_key("welcome", [did])
    assert Repo.get(Effect, effect_key) == nil
  end

  test "stores a mention-aware simulated welcome without a protocol write" do
    System.put_env("DELVETOWN_WRITE_ENABLED", "false")
    System.put_env("DELVETOWN_DRY_RUN_MARK_ACTIONED", "true")

    did = "did:plc:dry-member"
    joined_at = recent_time(-10)
    configure_members([member(did, joined_at)], introduction_feed(did))
    welcome_decision("What are you building with OTP?")

    assert {:ok, state} = run()
    assert state.last_run.status == "simulated"
    assert state.last_run.effects == 0
    refute_received {:create_record, _collection, _record, _rkey}

    event_key = InteractionLedger.event_key("new_member", [did])
    event = Repo.get!(InteractionEvent, event_key)
    assert event.state == "completed"
    assert event.payload["text"] == "@dry-member.delve.town What are you building with OTP?"

    assert event.payload["publication_actor"] == %{
             "did" => did,
             "handle" => "dry-member.delve.town"
           }

    assert event.payload["publication_target"]["uri"] ==
             "at://#{did}/town.delve.feed.post/3mx6intro"

    assert Repo.get(Effect, Protocol.effect_key("welcome", [did])) == nil
  end

  defp run(state \\ Agent.new!().state) do
    Jido.Exec.run(MemberDiscoveryCycle, %{mode: "normal"}, %{agent_state: state})
  end

  defp configure_members(actors, feed \\ [], profile \\ nil) do
    actor = List.first(actors) || %{}
    profile = profile || Map.take(actor, ["did", "handle", "displayName"])

    Application.put_env(:jido_delvetown, :query_results, %{
      "town.delve.membership.getMembership" => {:ok, %{"status" => "member"}},
      "town.delve.actor.searchActors" => {:ok, %{"actors" => actors}},
      "town.delve.actor.getProfile" => {:ok, profile},
      "town.delve.feed.getAuthorFeed" => {:ok, %{"feed" => feed}}
    })
  end

  defp introduction_feed(did) do
    uri = "at://#{did}/town.delve.feed.post/3mx6intro"

    [
      %{
        "post" => %{
          "uri" => uri,
          "cid" => "bafyreintro",
          "author" => %{
            "did" => did,
            "handle" => String.replace_prefix(did, "did:plc:", "") <> ".delve.town"
          },
          "record" => %{"text" => "Hello DelveTown. This is my first post."}
        }
      }
    ]
  end

  defp welcome_decision(text) do
    Application.put_env(
      :jido_delvetown,
      :decision_result,
      {:ok,
       %{
         action: "welcome",
         text: text,
         topic: "new member",
         reason: "A specific and useful welcome"
       }}
    )
  end

  defp member(did, joined_at) do
    %{
      "did" => did,
      "handle" => String.replace_prefix(did, "did:plc:", "") <> ".delve.town",
      "displayName" => "New Member",
      "description" => "Learning OTP and supervised agent design.",
      "createdAt" => joined_at,
      "indexedAt" => joined_at
    }
  end

  defp recent_time(minutes) do
    DateTime.utc_now()
    |> DateTime.add(minutes, :minute)
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
