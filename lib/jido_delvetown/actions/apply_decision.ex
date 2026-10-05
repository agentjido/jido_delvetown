defmodule JidoDelvetown.Actions.ApplyDecision do
  @moduledoc "Validates and applies one participation decision under write guards."

  use Jido.Action,
    name: "delvetown_apply_decision",
    schema: Zoi.object(%{cycle: Zoi.map()})

  alias JidoDelvetown.Actions.{CreatePost, LikePost, ReplyToPost, RepostPost}
  alias JidoDelvetown.Config

  @impl true
  def run(%{cycle: %{status: "failed"} = cycle}, _context), do: {:ok, cycle}

  def run(%{cycle: cycle}, _context) do
    with :ok <- validate(cycle) do
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

  defp apply(%{mode: "review"} = cycle),
    do: Map.merge(cycle, %{status: "proposed", effects: 0, receipt: nil})

  defp apply(%{mode: "normal"} = cycle) do
    if Config.write_enabled?() do
      case execute(cycle.decision, cycle.candidate) do
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
    else
      Map.merge(cycle, %{status: "proposed", effects: 0, receipt: nil})
    end
  end

  defp validate(cycle) do
    action = cycle.decision.action

    cond do
      action not in cycle.allowed_actions ->
        {:error, :action_not_allowed_for_intent}

      action in ["reply", "post"] and not valid_text?(cycle.decision.text) ->
        {:error, :invalid_post_text}

      action == "reply" and not valid_reply_target?(cycle.candidate) ->
        {:error, :invalid_reply_target}

      action in ["like", "repost"] and not valid_subject?(cycle.candidate) ->
        {:error, :invalid_subject}

      true ->
        :ok
    end
  end

  defp execute(%{action: "reply", text: text}, candidate) do
    ReplyToPost.run(
      %{
        text: text,
        parent_uri: candidate.uri,
        parent_cid: candidate.cid,
        root_uri: candidate.root.uri,
        root_cid: candidate.root.cid,
        langs: ["en"]
      },
      %{}
    )
  end

  defp execute(%{action: "like"}, candidate),
    do: LikePost.run(%{uri: candidate.uri, cid: candidate.cid}, %{})

  defp execute(%{action: "repost"}, candidate),
    do: RepostPost.run(%{uri: candidate.uri, cid: candidate.cid}, %{})

  defp execute(%{action: "post", text: text}, _candidate),
    do: CreatePost.run(%{text: text, langs: ["en"]}, %{})

  defp valid_text?(text), do: is_binary(text) and String.length(text) in 1..300

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

  defp effect_count(%{reused?: true}), do: 0
  defp effect_count(_receipt), do: 1

  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(_reason), do: "operation_failed"
end
