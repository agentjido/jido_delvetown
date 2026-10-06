defmodule JidoDelvetown.ManualPublisher do
  @moduledoc "Publishes one selected simulated draft under a separate manual write guard."

  alias JidoDelvetown.{
    ActorMemory,
    Candidate,
    Config,
    ConversationMemory,
    InteractionEvents,
    OutgoingLikePolicy,
    Protocol,
    Store,
    WelcomePost
  }

  alias JidoDelvetown.Storage.InteractionEvent

  @post_collection "town.delve.feed.post"
  @like_collection "town.delve.feed.like"
  @supported_actions ["like", "post", "reply", "welcome"]

  def publish(event_key) when is_binary(event_key) and event_key != "" do
    with :ok <- enabled(),
         %InteractionEvent{} = event <- InteractionEvents.get(event_key),
         :ok <- publishable(event),
         {:ok, result, effect_key} <- publish_event(event),
         publication = event |> publication_details(result, effect_key),
         {:ok, _event} <- InteractionEvents.record_manual_publication(event_key, publication) do
      _result =
        Store.add_event(:manual_publish, %{
          event_key: event_key,
          effect_key: effect_key,
          record_uri: publication.uri,
          reused?: result.reused?
        })

      {:ok, publication}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def publish(_event_key), do: {:error, :invalid_event_key}

  defp enabled do
    if Config.manual_publish_enabled?(),
      do: :ok,
      else: {:error, :manual_publish_disabled}
  end

  defp publishable(%InteractionEvent{state: "completed", payload: payload}) do
    action = value(payload, :action)

    cond do
      value(payload, :cycle_status) != "simulated" ->
        {:error, :not_simulated}

      action not in @supported_actions ->
        {:error, :unsupported_action}

      action != "like" and not valid_text?(value(payload, :text)) ->
        {:error, :invalid_draft_text}

      true ->
        :ok
    end
  end

  defp publishable(%InteractionEvent{state: state}),
    do: {:error, {:invalid_event_state, state}}

  defp publish_event(%InteractionEvent{payload: payload} = event) do
    case value(payload, :action) do
      "like" -> publish_like(event)
      "reply" -> publish_reply(event)
      "post" -> publish_post(event)
      "welcome" -> publish_welcome(event)
    end
  end

  defp publish_like(%InteractionEvent{} = event) do
    with {:ok, target} <- saved_like_target(event),
         {:ok, candidate} <- fetch_like_candidate(target.uri),
         :ok <- validate_live_like_target(candidate, target, event.actor_did),
         effect_key = Protocol.effect_key("like", [target.uri]),
         {:ok, result} <- publish_like_candidate(event, candidate, target, effect_key) do
      {:ok, result, effect_key}
    end
  end

  defp publish_like_candidate(event, candidate, target, effect_key) do
    case Store.effect(effect_key) do
      nil ->
        with :ok <- current_like_eligibility(candidate, event.event_key) do
          create_manual_like(event, target, effect_key)
        end

      effect ->
        with :ok <- validate_existing_like_effect(effect, target.uri) do
          create_manual_like(event, target, effect_key)
        end
    end
  end

  defp create_manual_like(event, target, effect_key) do
    Protocol.create_manual_record(
      effect_key,
      @like_collection,
      %{
        subject: %{uri: target.uri, cid: target.cid},
        created_at: Protocol.now()
      },
      subject_key: target.uri,
      actor_did: event.actor_did
    )
  end

  defp saved_like_target(%InteractionEvent{} = event) do
    target = value(event.payload, :publication_target, %{})
    uri = value(target, :uri)
    cid = value(target, :cid)

    cond do
      not valid_post_uri?(uri) or not present?(cid) -> {:error, :missing_like_target}
      event.record_uri != uri -> {:error, :like_target_mismatch}
      true -> {:ok, %{uri: uri, cid: cid}}
    end
  end

  defp fetch_like_candidate(uri) do
    with {:ok, response} <-
           Protocol.query("town.delve.feed.getPostThread", %{
             uri: uri,
             depth: 0,
             parent_height: 0
           }),
         %{post: candidate} <- Candidate.thread(response) do
      {:ok, Map.put(candidate, :memory, memory_context(candidate))}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :like_target_unavailable}
    end
  end

  defp validate_live_like_target(candidate, target, actor_did) do
    cond do
      candidate.uri != target.uri -> {:error, :like_target_mismatch}
      candidate.cid != target.cid -> {:error, :like_target_changed}
      get_in(candidate, [:author, :did]) != actor_did -> {:error, :like_target_changed}
      true -> :ok
    end
  end

  defp current_like_eligibility(candidate, event_key) do
    case OutgoingLikePolicy.evaluate(candidate, %{},
           exclude_event_key: event_key,
           local_effect?: false
         ) do
      :ok -> :ok
      {:skip, reason} -> {:error, {:like_not_eligible, reason}}
    end
  end

  defp validate_existing_like_effect(
         %{collection: @like_collection, subject_key: subject_key},
         subject_key
       ),
       do: :ok

  defp validate_existing_like_effect(_effect, _subject_key),
    do: {:error, :like_effect_mismatch}

  defp publish_reply(%InteractionEvent{} = event) do
    with {:ok, target} <- reply_target(event),
         effect_key = Protocol.effect_key("reply", [target.uri]),
         {:ok, result} <-
           Protocol.create_manual_record(
             effect_key,
             @post_collection,
             %{
               text: value(event.payload, :text),
               langs: ["en"],
               created_at: Protocol.now(),
               reply: %{
                 root: target.root,
                 parent: %{uri: target.uri, cid: target.cid}
               }
             },
             subject_key: target.uri,
             actor_did: event.actor_did
           ) do
      {:ok, result, effect_key}
    end
  end

  defp publish_post(%InteractionEvent{} = event) do
    opportunity_id = event.source_id || event.event_key
    effect_key = Protocol.effect_key("post", [opportunity_id])

    with {:ok, result} <-
           Protocol.create_manual_record(
             effect_key,
             @post_collection,
             top_level_record(event),
             subject_key: opportunity_id
           ) do
      {:ok, result, effect_key}
    end
  end

  defp publish_welcome(%InteractionEvent{actor_did: did} = event)
       when is_binary(did) and did != "" do
    effect_key = Protocol.effect_key("welcome", [did])

    with {:ok, handle} <- welcome_handle(event, did),
         {:ok, identity} <- WelcomePost.resolve_identity(did, handle),
         {:ok, text} <- WelcomePost.render_text(value(event.payload, :text), identity.handle),
         target = welcome_target(event.payload, did),
         {:ok, record} <- WelcomePost.record(text, did, identity.handle, target),
         {:ok, result} <-
           Protocol.create_manual_record(
             effect_key,
             @post_collection,
             record,
             subject_key: did,
             actor_did: did
           ) do
      {:ok, result, effect_key}
    end
  end

  defp publish_welcome(_event), do: {:error, :missing_actor}

  defp welcome_handle(event, did) do
    saved_actor = value(event.payload, :publication_actor, %{})

    case value(saved_actor, :handle) do
      handle when is_binary(handle) and handle != "" ->
        {:ok, handle}

      _missing ->
        case ActorMemory.get(did) do
          %{handle: handle} when is_binary(handle) and handle != "" -> {:ok, handle}
          _actor -> {:error, :missing_actor_handle}
        end
    end
  end

  defp welcome_target(payload, did) do
    case WelcomePost.safe_reply_target(value(payload, :publication_target, %{}), did) do
      {:ok, target} -> target
      {:error, _reason} -> nil
    end
  end

  defp memory_context(candidate) do
    %{
      actor: ActorMemory.context(get_in(candidate, [:author, :did])),
      conversation: ConversationMemory.context(get_in(candidate, [:root, :uri]))
    }
  end

  defp top_level_record(event) do
    %{
      text: value(event.payload, :text),
      langs: ["en"],
      created_at: Protocol.now()
    }
  end

  defp reply_target(%InteractionEvent{} = event) do
    case saved_reply_target(event.payload) do
      {:ok, target} -> {:ok, target}
      {:error, :missing_reply_target} -> fetch_reply_target(event.record_uri)
    end
  end

  defp saved_reply_target(payload) do
    target = value(payload, :publication_target, %{})
    root = value(target, :root, %{})

    validate_reply_target(%{
      uri: value(target, :uri),
      cid: value(target, :cid),
      root: %{uri: value(root, :uri), cid: value(root, :cid)}
    })
  end

  defp fetch_reply_target(uri) when is_binary(uri) and uri != "" do
    with {:ok, response} <-
           Protocol.query("town.delve.feed.getPostThread", %{
             uri: uri,
             depth: 0,
             parent_height: 6
           }),
         %{post: post} <- Candidate.thread(response),
         true <- post.uri == uri,
         {:ok, target} <- validate_reply_target(post) do
      {:ok, target}
    else
      false -> {:error, :reply_target_mismatch}
      nil -> {:error, :missing_reply_target}
      {:error, _reason} = error -> error
      _invalid -> {:error, :missing_reply_target}
    end
  end

  defp fetch_reply_target(_uri), do: {:error, :missing_reply_target}

  defp validate_reply_target(%{uri: uri, cid: cid, root: %{uri: root_uri, cid: root_cid}})
       when is_binary(uri) and uri != "" and is_binary(cid) and cid != "" and
              is_binary(root_uri) and root_uri != "" and is_binary(root_cid) and root_cid != "" do
    {:ok, %{uri: uri, cid: cid, root: %{uri: root_uri, cid: root_cid}}}
  end

  defp validate_reply_target(_target), do: {:error, :missing_reply_target}

  defp publication_details(event, result, effect_key) do
    receipt = result.receipt || %{}

    publication = %{
      status: "completed",
      published_at: Protocol.now(),
      uri: value(receipt, :uri),
      cid: value(receipt, :cid),
      effect_key: effect_key,
      reused?: result.reused?,
      reconciled?: Map.get(result, :reconciled?, false)
    }

    maybe_add_like_target(publication, event)
  end

  defp maybe_add_like_target(publication, %InteractionEvent{payload: payload}) do
    if value(payload, :action) == "like" do
      target = value(payload, :publication_target, %{})

      publication
      |> Map.put(:target_uri, value(target, :uri))
      |> Map.put(:target_cid, value(target, :cid))
    else
      publication
    end
  end

  defp valid_post_uri?(uri) when is_binary(uri),
    do: Regex.match?(~r/\Aat:\/\/[^\/\s]+\/town\.delve\.feed\.post\/[^\/\s]+\z/, uri)

  defp valid_post_uri?(_uri), do: false

  defp present?(value), do: is_binary(value) and value != ""

  defp valid_text?(text), do: is_binary(text) and String.length(text) in 1..300

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp value(_map, _key, default), do: default
end
