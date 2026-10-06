defmodule JidoDelvetown.CycleRecorder do
  @moduledoc "Coordinates durable event, actor, relationship, and conversation updates."

  alias JidoDelvetown.{
    ActorMemory,
    ConversationMemory,
    InteractionEvents,
    RelationshipMemory
  }

  alias JidoDelvetown.Settings.Limits

  @terminal_states ["completed", "ignored", "failed"]
  @like_review_text_limit 500

  def record(cycle, decision, completed_at) do
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
          settings: Map.get(cycle, :settings),
          intent: cycle.intent,
          action: decision.action,
          cycle_status: cycle.status,
          text: Map.get(decision, :text),
          topic: Map.get(decision, :topic),
          image_prompt: Map.get(decision, :image_prompt),
          image_alt_text: Map.get(decision, :image_alt_text),
          image_generation: image_generation_receipt(Map.get(cycle, :image_generation)),
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
              with :ok <- ActorMemory.remember_social_signal(notification, cycle),
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
    with :ok <- ActorMemory.remember(candidate, cycle, decision, at),
         :ok <- RelationshipMemory.remember(candidate, cycle, decision, at),
         :ok <- ConversationMemory.remember(candidate, cycle, decision, at) do
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
    limit = like_limit(cycle)

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

  defp like_limit(%{limits: %{daily_like_limit: limit}}), do: limit

  defp like_limit(_cycle) do
    case Limits.fetch(:daily_like_limit) do
      {:ok, limit} -> limit
      {:error, _reason} -> 0
    end
  end

  defp bounded_like_text(candidate) do
    case Map.get(candidate, :text) || get_in(candidate, [:thread, :post, :text]) do
      text when is_binary(text) -> String.slice(text, 0, @like_review_text_limit)
      _text -> nil
    end
  end

  defp image_generation_receipt(nil), do: nil

  defp image_generation_receipt(result) do
    Map.take(result, [
      :draft_id,
      :generation_request_id,
      :artifact_digest,
      :draft_state,
      :generation_state,
      :provider_call_performed?,
      :reused?,
      :uploaded_by_command?,
      :published_by_command?,
      :provenance,
      :usage,
      :settings
    ])
  end

  defp candidate_event_key(kind, id) do
    InteractionEvents.event_key("candidate", [kind, id])
  end

  defp cycle_outcome("failed"), do: :failed
  defp cycle_outcome(status) when status in ["ignored", "skipped"], do: :ignored
  defp cycle_outcome(_status), do: :completed

  defp cycle_failure(%{errors: errors}) when errors != [], do: %{errors: errors}
  defp cycle_failure(_cycle), do: %{}
end
