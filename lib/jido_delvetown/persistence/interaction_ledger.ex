defmodule JidoDelvetown.InteractionLedger do
  @moduledoc "Durable interaction, actor, and conversation memory."

  alias JidoDelvetown.{Config, FriendList, InteractionEvents, Repo}
  alias JidoDelvetown.Storage.{Actor, Conversation}

  @terminal_states ["completed", "ignored", "failed"]
  @like_review_text_limit 500

  def event_key(kind, values), do: InteractionEvents.event_key(kind, values)

  def observe_candidates(candidates, opts \\ []),
    do: InteractionEvents.observe_candidates(candidates, opts)

  def observe(attrs, opts \\ []), do: InteractionEvents.observe(attrs, opts)
  def claim(event_key, opts \\ []), do: InteractionEvents.claim(event_key, opts)

  def finish(event_key, outcome, details \\ %{}, opts \\ []),
    do: InteractionEvents.finish(event_key, outcome, details, opts)

  def recover_stale_claims(opts \\ []), do: InteractionEvents.recover_stale_claims(opts)

  def record_cycle(cycle, decision, completed_at) do
    with :ok <- record_candidate(cycle, decision, completed_at),
         :ok <- finish_ignored_notifications(cycle) do
      :ok
    end
  end

  defp record_candidate(%{candidate: nil}, _decision, _completed_at), do: :ok
  defp record_candidate(%{defer?: true}, _decision, _completed_at), do: :ok

  defp record_candidate(cycle, decision, completed_at) do
    candidate = cycle.candidate
    event_key = Map.get(candidate, :event_key) || candidate_event_key(cycle.kind, candidate.id)
    actor_did = get_in(candidate, [:author, :did])

    attrs = %{
      event_key: event_key,
      kind: Map.get(candidate, :reason, cycle.kind),
      actor_did: actor_did,
      record_uri: Map.get(candidate, :uri),
      source_id: candidate.id,
      occurred_at: Map.get(candidate, :indexed_at) || completed_at,
      payload:
        %{
          cycle_kind: cycle.kind,
          mode: cycle.mode,
          intent: cycle.intent,
          action: decision.action,
          cycle_status: cycle.status,
          text: Map.get(decision, :text),
          topic: Map.get(decision, :topic),
          model_reason: Map.get(decision, :reason),
          response_format: Map.get(decision, :format),
          selection: Map.get(cycle, :selection, %{}),
          publication_target: publication_target(candidate)
        }
        |> maybe_add_publication_actor(decision, candidate)
        |> maybe_add_like_review(cycle, decision, candidate, completed_at)
    }

    with {:ok, _event} <- InteractionEvents.observe(attrs),
         {:ok, event_result} <- finish_candidate(event_key, cycle),
         :ok <- remember_candidate(event_result, candidate, cycle, decision, completed_at) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish_ignored_notifications(cycle) do
    cycle
    |> Map.get(:notifications, [])
    |> Enum.reduce_while(:ok, fn notification, :ok ->
      case get_in(cycle, [:state, :notifications, :processed, notification.id, :status]) do
        status when status in ["ignored", "skipped"] ->
          case InteractionEvents.claim(notification.event_key) do
            {:ok, _claimed} ->
              with :ok <- remember_social_signal(notification, cycle),
                   {:ok, _event} <-
                     InteractionEvents.finish(notification.event_key, :ignored, %{
                       reason: "policy_skip"
                     }) do
                {:cont, :ok}
              else
                {:error, reason} -> {:halt, {:error, reason}}
              end

            {:error, {:not_claimable, state}} when state in @terminal_states ->
              {:cont, :ok}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        _status ->
          {:cont, :ok}
      end
    end)
  end

  def actor(did, opts \\ []), do: repo(opts).get(Actor, did)
  def conversation(root_uri, opts \\ []), do: repo(opts).get(Conversation, root_uri)
  def event(event_key, opts \\ []), do: InteractionEvents.get(event_key, opts)

  def record_manual_publication(event_key, details, opts \\ []),
    do: InteractionEvents.record_manual_publication(event_key, details, opts)

  def processable_event?(event_key, opts \\ []),
    do: InteractionEvents.processable?(event_key, opts)

  def pending_events?(kinds, opts \\ []), do: InteractionEvents.pending?(kinds, opts)

  def outreach_count(kind, since, opts \\ []),
    do: InteractionEvents.outreach_count(kind, since, opts)

  def recent_outreach_for_actor?(kind, actor_did, since, opts \\ []),
    do: InteractionEvents.recent_outreach_for_actor?(kind, actor_did, since, opts)

  defp finish_candidate(_event_key, %{status: "proposed"}), do: {:ok, :pending}

  defp finish_candidate(event_key, cycle) do
    with {:ok, _claimed} <- InteractionEvents.claim(event_key),
         {:ok, _finished} <-
           InteractionEvents.finish(
             event_key,
             cycle_outcome(cycle.status),
             cycle_failure(cycle)
           ) do
      {:ok, :finished}
    else
      {:error, {:not_claimable, state}} when state in @terminal_states ->
        {:ok, :already_terminal}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remember_candidate(:already_terminal, _candidate, _cycle, _decision, _at), do: :ok

  defp remember_candidate(_result, candidate, cycle, decision, at) do
    with :ok <- remember_actor(candidate, cycle, decision, at),
         :ok <- remember_relationship(candidate, cycle, decision, at),
         :ok <- remember_conversation(candidate, cycle, decision, at) do
      :ok
    end
  end

  defp publication_target(candidate) do
    %{
      uri: Map.get(candidate, :uri),
      cid: Map.get(candidate, :cid),
      root: Map.get(candidate, :root)
    }
  end

  defp maybe_add_publication_actor(payload, %{action: "welcome"}, candidate) do
    Map.put(payload, :publication_actor, %{
      did: get_in(candidate, [:author, :did]),
      handle: get_in(candidate, [:author, :handle])
    })
  end

  defp maybe_add_publication_actor(payload, _decision, _candidate), do: payload

  defp maybe_add_like_review(payload, cycle, %{action: "like"}, candidate, selected_at) do
    likes = get_in(cycle, [:state, :budget, :likes]) || 0
    limit = Config.daily_like_limit()

    Map.put(payload, :like_review, %{
      author: %{
        did: get_in(candidate, [:author, :did]),
        handle: get_in(candidate, [:author, :handle]),
        display_name: get_in(candidate, [:author, :display_name])
      },
      post_text: bounded_like_text(candidate),
      selected_at: selected_at,
      budget: %{
        date: get_in(cycle, [:state, :budget, :date]),
        likes: likes,
        limit: limit,
        remaining: max(limit - likes, 0)
      }
    })
  end

  defp maybe_add_like_review(payload, _cycle, _decision, _candidate, _selected_at),
    do: payload

  defp bounded_like_text(candidate) do
    case Map.get(candidate, :text) || get_in(candidate, [:thread, :post, :text]) do
      text when is_binary(text) -> String.slice(text, 0, @like_review_text_limit)
      _text -> nil
    end
  end

  def context_for(candidate, opts \\ []) when is_map(candidate) do
    actor = maybe_actor(get_in(candidate, [:author, :did]), opts)
    conversation = maybe_conversation(get_in(candidate, [:root, :uri]), opts)

    %{
      actor: actor_context(actor),
      conversation: conversation_context(conversation)
    }
  end

  def events_terminal?(candidates, opts \\ []),
    do: InteractionEvents.all_terminal?(candidates, opts)

  def prune(opts \\ []), do: InteractionEvents.prune(opts)

  defp remember_actor(%{author: %{did: did} = author}, cycle, decision, at)
       when is_binary(did) do
    repo = Repo
    seen_at = parse_time(at)
    contacted? = cycle.status in ["acted", "simulated"]
    opted_out? = Map.get(cycle.candidate, :opt_out?, false)
    welcome_status = welcome_status(cycle, decision, contacted?)

    repo.transaction(
      fn ->
        case repo.get(Actor, did) do
          nil ->
            %Actor{
              did: did,
              handle: Map.get(author, :handle),
              display_name: Map.get(author, :display_name),
              profile: json_safe(author),
              first_seen_at: seen_at,
              last_seen_at: seen_at,
              last_interaction_at: if(contacted?, do: seen_at),
              contact_count: if(contacted?, do: 1, else: 0),
              welcome_status: welcome_status,
              opted_out: opted_out?,
              metadata: actor_metadata(%{}, cycle.candidate, seen_at)
            }
            |> repo.insert!()

          actor ->
            actor
            |> Ecto.Changeset.change(
              handle: Map.get(author, :handle) || actor.handle,
              display_name: Map.get(author, :display_name) || actor.display_name,
              profile: Map.merge(actor.profile || %{}, json_safe(author)),
              last_seen_at: seen_at,
              last_interaction_at: if(contacted?, do: seen_at, else: actor.last_interaction_at),
              contact_count: actor.contact_count + if(contacted?, do: 1, else: 0),
              welcome_status: welcome_status || actor.welcome_status,
              opted_out: actor.opted_out || opted_out?,
              metadata: actor_metadata(actor.metadata || %{}, cycle.candidate, seen_at)
            )
            |> repo.update!()
        end
      end,
      mode: :immediate
    )
    |> transaction_ok()
  end

  defp remember_actor(_candidate, _cycle, _decision, _at), do: :ok

  defp remember_social_signal(%{reason: "like"} = candidate, cycle) do
    observed_at = candidate.indexed_at || now()
    ignored_cycle = %{cycle | candidate: candidate, status: "ignored"}
    remember_actor(candidate, ignored_cycle, %{action: "skip"}, observed_at)
  end

  defp remember_social_signal(_candidate, _cycle), do: :ok

  defp actor_metadata(metadata, %{reason: "like", event_key: event_key}, observed_at)
       when is_binary(event_key) do
    entry = %{
      "event_key" => event_key,
      "observed_at" => DateTime.to_iso8601(observed_at)
    }

    prior_likes =
      metadata
      |> Map.get("incoming_likes", [])
      |> List.wrap()
      |> Enum.filter(&is_map/1)

    likes =
      [entry | prior_likes]
      |> Enum.uniq_by(&Map.get(&1, "event_key"))
      |> Enum.take(20)

    Map.put(metadata, "incoming_likes", likes)
  end

  defp actor_metadata(metadata, _candidate, _observed_at), do: metadata

  defp remember_relationship(candidate, cycle, decision, at) do
    with :ok <- remember_follower(candidate, at),
         :ok <- remember_friend_references(cycle, decision) do
      :ok
    end
  end

  defp remember_follower(%{reason: "follow", author: %{did: did}}, at)
       when is_binary(did) do
    case FriendList.record_follows_agent(did, at) do
      {:ok, _relationship} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp remember_follower(_candidate, _at), do: :ok

  defp remember_friend_references(%{status: status}, %{text: text})
       when status in ["acted", "simulated"] and is_binary(text) do
    FriendList.record_text_references(text)
  end

  defp remember_friend_references(_cycle, _decision), do: :ok

  defp welcome_status(%{status: "simulated"}, %{action: "welcome"}, true), do: "simulated"
  defp welcome_status(_cycle, %{action: "welcome"}, true), do: "completed"
  defp welcome_status(_cycle, _decision, _contacted?), do: nil

  defp remember_conversation(candidate, %{status: status}, %{action: "reply"}, at)
       when status in ["acted", "simulated"] do
    root_uri = get_in(candidate, [:root, :uri])

    if is_binary(root_uri) do
      repo = Repo
      action_at = parse_time(at)

      repo.transaction(
        fn ->
          case repo.get(Conversation, root_uri) do
            nil ->
              %Conversation{
                root_uri: root_uri,
                actor_did: get_in(candidate, [:author, :did]),
                turn_count: 1,
                last_record_uri: Map.get(candidate, :uri),
                last_action: "reply",
                last_action_at: action_at,
                status: "active",
                metadata: conversation_metadata(candidate)
              }
              |> repo.insert!()

            conversation ->
              conversation
              |> Ecto.Changeset.change(
                actor_did: get_in(candidate, [:author, :did]) || conversation.actor_did,
                turn_count: conversation.turn_count + 1,
                last_record_uri: Map.get(candidate, :uri),
                last_action: "reply",
                last_action_at: action_at,
                status: "active",
                metadata:
                  Map.merge(conversation.metadata || %{}, conversation_metadata(candidate))
              )
              |> repo.update!()
          end
        end,
        mode: :immediate
      )
      |> transaction_ok()
    else
      :ok
    end
  end

  defp remember_conversation(candidate, %{reason: reason}, _decision, _at)
       when reason in [
              "actor_opt_out",
              "conversation_closed",
              "conversation_turn_limit",
              "conversation_too_old",
              "conversation_non_response_limit"
            ] do
    root_uri = get_in(candidate, [:root, :uri])

    case if(is_binary(root_uri), do: Repo.get(Conversation, root_uri)) do
      nil ->
        :ok

      conversation ->
        conversation
        |> Ecto.Changeset.change(status: "closed")
        |> Repo.update()
        |> case do
          {:ok, _conversation} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp remember_conversation(_candidate, _cycle, _decision, _at), do: :ok

  defp transaction_ok({:ok, _value}), do: :ok
  defp transaction_ok({:error, reason}), do: {:error, reason}

  defp cycle_outcome("failed"), do: :failed
  defp cycle_outcome(status) when status in ["ignored", "skipped"], do: :ignored
  defp cycle_outcome(_status), do: :completed

  defp cycle_failure(%{errors: errors}) when errors != [], do: %{errors: errors}
  defp cycle_failure(_cycle), do: %{}

  defp actor_context(nil), do: nil

  defp actor_context(actor) do
    %{
      did: actor.did,
      handle: actor.handle,
      display_name: actor.display_name,
      first_seen_at: iso8601(actor.first_seen_at),
      last_interaction_at: iso8601(actor.last_interaction_at),
      contact_count: actor.contact_count,
      welcome_status: actor.welcome_status,
      opted_out: actor.opted_out
    }
  end

  defp conversation_context(nil), do: nil

  defp conversation_context(conversation) do
    %{
      root_uri: conversation.root_uri,
      turn_count: conversation.turn_count,
      last_record_uri: conversation.last_record_uri,
      last_action: conversation.last_action,
      last_action_at: iso8601(conversation.last_action_at),
      status: conversation.status,
      unanswered_follow_ups: Map.get(conversation.metadata || %{}, "unanswered_follow_ups", 0)
    }
  end

  defp conversation_metadata(candidate) do
    %{
      "last_inbound_event_key" => Map.get(candidate, :event_key),
      "last_inbound_record_uri" => Map.get(candidate, :uri),
      "unanswered_follow_ups" => 0
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp maybe_actor(did, opts) when is_binary(did), do: actor(did, opts)
  defp maybe_actor(_did, _opts), do: nil

  defp maybe_conversation(root_uri, opts) when is_binary(root_uri),
    do: conversation(root_uri, opts)

  defp maybe_conversation(_root_uri, _opts), do: nil

  defp candidate_event_key(kind, id) do
    InteractionEvents.event_key("candidate", [kind, id])
  end

  defp parse_time(%DateTime{} = value), do: microsecond(value)

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> microsecond(time)
      _error -> now()
    end
  end

  defp parse_time(_value), do: now()

  defp microsecond(value) do
    value |> DateTime.to_unix(:microsecond) |> DateTime.from_unix!(:microsecond)
  end

  defp json_safe(nil), do: nil
  defp json_safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_safe(item)} end)
  end

  defp json_safe(value), do: inspect(value)

  defp repo(opts), do: Keyword.get(opts, :repo, Repo)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
