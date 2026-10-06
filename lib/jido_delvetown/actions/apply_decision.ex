defmodule JidoDelvetown.Actions.ApplyDecision do
  @moduledoc "Validates and applies one participation decision under write guards."

  use Jido.Action,
    name: "delvetown_apply_decision",
    schema: Zoi.object(%{cycle: Zoi.map()})

  alias JidoDelvetown.Actions.{
    CreatePost,
    FollowActor,
    LikePost,
    ReplyToPost,
    RepostPost,
    WelcomeActor
  }

  alias JidoDelvetown.{OutgoingLikePolicy, ParticipationImageGeneration, WelcomePost}
  alias JidoDelvetown.Settings.Behavior

  @impl true
  def run(%{cycle: %{status: "failed"} = cycle}, _context), do: {:ok, cycle}

  def run(%{cycle: cycle}, _context) do
    cycle = discard_invalid_image_proposal(cycle)

    with :ok <- validate(cycle),
         {:ok, cycle} <- prepare_welcome(cycle) do
      {:ok, apply(cycle)}
    else
      {:error, reason} ->
        {:ok,
         Map.merge(cycle, %{
           status: "failed",
           stage: "decision_validation",
           errors: cycle.errors ++ [error_text(reason)]
         })}
    end
  end

  defp apply(%{decision: %{action: "skip"}} = cycle),
    do: Map.merge(cycle, %{status: "skipped", effects: 0, receipt: nil})

  defp apply(%{decision: %{action: "acknowledge"}} = cycle),
    do: Map.merge(cycle, %{status: "acknowledged", effects: 0, receipt: nil})

  defp apply(%{decision: decision} = cycle) when is_map_key(decision, :image_prompt) do
    generate_image_draft(cycle)
  end

  defp apply(%{decision: decision} = cycle) when is_map_key(decision, :image_alt_text) do
    generate_image_draft(cycle)
  end

  defp apply(cycle) do
    case Behavior.action_disposition(cycle.mode) do
      {:ok, :propose} ->
        complete_without_effect(cycle, "proposed")

      {:ok, :simulate} ->
        complete_without_effect(cycle, "simulated")

      {:ok, :execute} ->
        execute_decision(cycle)

      {:error, reason} ->
        Map.merge(cycle, %{
          status: "failed",
          stage: "autonomy_policy",
          effects: 0,
          receipt: nil,
          errors: cycle.errors ++ [error_text(reason)]
        })
    end
  end

  defp complete_without_effect(cycle, status) do
    Map.merge(cycle, %{status: status, effects: 0, receipt: nil})
  end

  defp execute_decision(cycle) do
    case execute(cycle.decision, cycle.candidate, cycle) do
      {:ok, receipt} ->
        Map.merge(cycle, %{
          status: "acted",
          effects: effect_count(receipt),
          receipt: receipt
        })

      {:error, reason} ->
        Map.merge(cycle, %{
          status: "failed",
          stage: "effect",
          effects: 0,
          receipt: nil,
          errors: cycle.errors ++ [error_text(reason)]
        })
    end
  end

  defp validate(cycle) do
    action = cycle.decision.action

    like_eligibility =
      validate_like(action, cycle.candidate, cycle.state, cycle.limits, cycle.mode)

    cond do
      action not in cycle.allowed_actions ->
        {:error, :action_not_allowed_for_intent}

      not Behavior.action_enabled?(action) ->
        {:error, :action_disabled}

      action in ["reply", "post"] and not valid_text?(cycle.decision.text) ->
        {:error, :invalid_post_text}

      action == "welcome" and not valid_text?(cycle.decision.text) ->
        {:error, :invalid_welcome_text}

      image_proposal?(cycle.decision) and not valid_image_proposal?(cycle.decision) ->
        {:error, :invalid_participation_image_proposal}

      action == "reply" and not valid_reply_target?(cycle.candidate) ->
        {:error, :invalid_reply_target}

      action in ["like", "repost"] and not valid_subject?(cycle.candidate) ->
        {:error, :invalid_subject}

      like_eligibility != :ok ->
        like_eligibility

      action == "follow" and not valid_actor?(cycle.candidate) ->
        {:error, :invalid_actor}

      action == "welcome" and not valid_welcome_actor?(cycle.candidate) ->
        {:error, :invalid_welcome_actor}

      true ->
        :ok
    end
  end

  defp execute(%{action: "reply", text: text}, candidate, cycle) do
    ReplyToPost.run(
      %{
        text: text,
        parent_uri: candidate.uri,
        parent_cid: candidate.cid,
        root_uri: candidate.root.uri,
        root_cid: candidate.root.cid,
        langs: ["en"]
      },
      effect_context(cycle)
    )
  end

  defp execute(%{action: "like"}, candidate, cycle),
    do:
      LikePost.run(
        %{uri: candidate.uri, cid: candidate.cid},
        effect_context(cycle)
      )

  defp execute(%{action: "repost"}, candidate, cycle),
    do:
      RepostPost.run(
        %{uri: candidate.uri, cid: candidate.cid},
        effect_context(cycle)
      )

  defp execute(%{action: "post", text: text}, candidate, cycle),
    do:
      CreatePost.run(
        %{
          opportunity_id: candidate.id,
          text: text,
          langs: ["en"]
        },
        effect_context(cycle)
      )

  defp execute(%{action: "follow"}, candidate, cycle),
    do:
      FollowActor.run(
        %{did: candidate.author.did},
        effect_context(cycle)
      )

  defp execute(%{action: "welcome", text: text}, candidate, cycle),
    do:
      WelcomeActor.run(
        %{
          did: candidate.author.did,
          handle: candidate.author.handle,
          text: text,
          target: welcome_target(candidate)
        },
        effect_context(cycle)
      )

  defp effect_context(cycle), do: %{settings: Map.get(cycle, :settings)}

  defp valid_text?(text), do: is_binary(text) and String.length(text) in 1..300

  defp image_proposal?(decision),
    do: Map.has_key?(decision, :image_prompt) or Map.has_key?(decision, :image_alt_text)

  defp valid_image_proposal?(%{
         action: "post",
         image_prompt: prompt,
         image_alt_text: alt_text
       }),
       do: valid_bounded_text?(prompt, 4_000) and valid_bounded_text?(alt_text, 1_000)

  defp valid_image_proposal?(_decision), do: false

  defp discard_invalid_image_proposal(%{decision: decision} = cycle) do
    if image_proposal?(decision) and not valid_image_proposal?(decision) do
      Map.put(cycle, :decision, Map.drop(decision, [:image_prompt, :image_alt_text]))
    else
      cycle
    end
  end

  defp valid_bounded_text?(text, limit),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= limit

  defp valid_reply_target?(%{
         uri: uri,
         cid: cid,
         root: %{uri: root_uri, cid: root_cid}
       }) do
    Enum.all?([uri, cid, root_uri, root_cid], &(is_binary(&1) and &1 != ""))
  end

  defp valid_reply_target?(_candidate), do: false

  defp valid_subject?(%{uri: uri, cid: cid}),
    do: is_binary(uri) and uri != "" and is_binary(cid) and cid != ""

  defp valid_subject?(_candidate), do: false

  defp validate_like("like", candidate, state, limits, mode) do
    case OutgoingLikePolicy.evaluate(candidate, state,
           limits: limits,
           allow_proposed?: simulation_promotion?(mode)
         ) do
      :ok -> :ok
      {:skip, reason} -> {:error, reason}
    end
  end

  defp validate_like(_action, _candidate, _state, _limits, _mode), do: :ok

  defp simulation_promotion?("normal"),
    do: Behavior.action_disposition("normal") == {:ok, :simulate}

  defp simulation_promotion?(_mode), do: false

  defp valid_actor?(%{author: %{did: did}}), do: is_binary(did) and did != ""
  defp valid_actor?(_candidate), do: false

  defp valid_welcome_actor?(%{author: %{did: did, handle: handle}}),
    do: WelcomePost.valid_identity?(did, handle)

  defp valid_welcome_actor?(_candidate), do: false

  defp prepare_welcome(%{decision: %{action: "welcome", text: text}} = cycle) do
    with {:ok, prepared} <- WelcomePost.prepare(cycle.candidate, text) do
      {:ok,
       cycle
       |> Map.put(:candidate, prepared.candidate)
       |> put_in([:decision, :text], prepared.text)
       |> Map.update!(:reads, &(&1 + prepared.reads))}
    end
  end

  defp prepare_welcome(cycle), do: {:ok, cycle}

  defp welcome_target(%{uri: uri, cid: cid, root: root})
       when not is_nil(uri) and not is_nil(cid) and not is_nil(root),
       do: %{uri: uri, cid: cid, root: root}

  defp welcome_target(_candidate), do: nil

  defp effect_count(%{reused?: true}), do: 0
  defp effect_count(_receipt), do: 1

  defp generate_image_draft(cycle) do
    case image_generation_module().generate(cycle, cycle.decision) do
      {:ok, result} ->
        Map.merge(cycle, %{
          status: "generated",
          effects: 0,
          receipt: nil,
          image_generation: result
        })

      {:error, reason} ->
        Map.merge(cycle, %{
          status: "failed",
          stage: "image_generation",
          effects: 0,
          receipt: nil,
          errors: cycle.errors ++ [error_text(reason)]
        })
    end
  end

  defp image_generation_module do
    Application.get_env(
      :jido_delvetown,
      :participation_image_generation,
      ParticipationImageGeneration
    )
  end

  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text({reason, _detail, _cause}) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(_reason), do: "operation_failed"
end
