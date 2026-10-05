defmodule JidoDelvetown.Actions.RecordCycle do
  @moduledoc "Records one completed participation cycle in the Agent state."

  use Jido.Action,
    name: "delvetown_record_cycle",
    schema: Zoi.object(%{cycle: Zoi.map()})

  alias JidoDelvetown.Actions.UpdateNotificationsSeen
  alias JidoDelvetown.Config
  alias JidoDelvetown.InteractionLedger
  alias JidoDelvetown.ScanProgress

  @topic_limit 10

  @impl true
  def run(%{cycle: cycle}, _context) do
    completed_at = now()
    decision = normalize_decision(cycle.decision)
    state = update_policy_state(cycle.state, cycle, decision, completed_at)
    result = result(cycle, decision, completed_at)
    {state, result} = maybe_mark_notifications_seen(state, cycle, result, completed_at)

    with :ok <- InteractionLedger.record_cycle(cycle, decision, completed_at),
         :ok <- finish_scan(cycle) do
      {:ok, finish_state(state, result, completed_at)}
    else
      {:error, reason} -> {:error, {:interaction_ledger_failed, reason}}
    end
  end

  defp finish_scan(%{scan: %{name: name, token: token}} = cycle) do
    result =
      if cycle.status == "failed" do
        ScanProgress.release(name, token)
      else
        ScanProgress.finish(name, token, Map.get(cycle.scan, :next_cursor))
      end

    case result do
      {:ok, _scan} -> :ok
      {:error, reason} -> {:error, {:scan_progress_failed, reason}}
    end
  end

  defp finish_scan(_cycle), do: :ok

  defp normalize_decision(decision) when map_size(decision) > 0, do: decision

  defp normalize_decision(_decision) do
    %{action: "skip", text: nil, topic: nil, reason: "Cycle did not reach a decision"}
  end

  defp result(cycle, decision, completed_at) do
    %{
      kind: cycle.kind,
      status: cycle.status,
      intent: cycle.intent,
      action: decision.action,
      candidate_id: candidate_id(cycle.candidate),
      record_uri: receipt_uri(cycle.receipt),
      summary: summary(cycle),
      proposal: Map.take(decision, [:text, :topic, :reason]),
      reads: cycle.reads,
      effects: cycle.effects,
      skips: if(cycle.status == "skipped", do: 1, else: 0),
      errors: cycle.errors,
      started_at: cycle.started_at,
      completed_at: completed_at
    }
  end

  defp summary(%{status: "failed", stage: stage}), do: "Cycle failed during #{stage}."

  defp summary(cycle),
    do:
      "#{String.capitalize(cycle.kind)} intent #{cycle.intent} selected " <>
        "#{cycle.decision.action}; cycle #{cycle.status}."

  defp update_policy_state(state, cycle, decision, at) do
    state =
      Map.put(
        state,
        :decision,
        Map.merge(decision, %{intent: cycle.intent, status: cycle.status})
      )

    state =
      if cycle.candidate && not cycle.defer? do
        put_processed(state, cycle.candidate, cycle.intent, decision.action, cycle.status, at)
      else
        state
      end

    if cycle.status == "acted" do
      state
      |> increment_budget(decision.action)
      |> update_conversation(cycle.candidate, decision.action, at)
      |> update_proactive(decision, at)
    else
      state
    end
  end

  defp put_processed(state, candidate, intent, action, status, at) do
    record = %{
      id: candidate.id,
      uri: Map.get(candidate, :uri),
      intent: intent,
      action: action,
      status: status,
      at: at
    }

    processed = Map.put(state.notifications.processed, candidate.id, record)
    put_in(state, [:notifications, :processed], processed)
  end

  defp increment_budget(state, action) when action in ["reply", "like", "repost"],
    do: put_in(state, [:budget, :replies], state.budget.replies + 1)

  defp increment_budget(state, "post"),
    do: put_in(state, [:budget, :posts], state.budget.posts + 1)

  defp increment_budget(state, _action), do: state

  defp update_conversation(state, candidate, "reply", at) do
    key = candidate.root.uri
    current = Map.get(state.conversations, key, %{turns: 0})

    record = %{
      root_uri: key,
      last_record_uri: candidate.uri,
      turns: current.turns + 1,
      last_action_at: at
    }

    Map.put(state, :conversations, Map.put(state.conversations, key, record))
  end

  defp update_conversation(state, _candidate, _action, _at), do: state

  defp update_proactive(state, %{action: "post"} = decision, at) do
    topics =
      case decision.topic do
        topic when is_binary(topic) and topic != "" -> [topic | state.proactive.recent_topics]
        _topic -> state.proactive.recent_topics
      end
      |> Enum.uniq()
      |> Enum.take(@topic_limit)

    Map.put(state, :proactive, %{last_post_at: at, recent_topics: topics})
  end

  defp update_proactive(state, _decision, _at), do: state

  defp maybe_mark_notifications_seen(state, cycle, result, at) do
    cond do
      cycle.kind != "reactive" or cycle.mode != "normal" or
          not Config.mark_notifications_seen?() ->
        {state, result}

      not all_notifications_terminal?(state, cycle.notifications) ->
        {state, result}

      true ->
        case UpdateNotificationsSeen.run(%{}, %{}) do
          {:ok, _receipt} ->
            notifications = Map.put(state.notifications, :last_seen_at, at)
            {Map.put(state, :notifications, notifications), result}

          {:error, reason} ->
            error = "notification_seen: #{error_text(reason)}"
            {state, Map.update!(result, :errors, &(&1 ++ [error]))}
        end
    end
  end

  defp all_notifications_terminal?(state, notifications) do
    notifications
    |> Enum.filter(& &1.unread?)
    |> Enum.all?(fn notification ->
      case state.notifications.processed[notification.id] do
        %{status: status} -> status in ["acted", "ignored", "skipped"]
        _missing -> false
      end
    end)
  end

  defp finish_state(state, result, completed_at) do
    last_cycle =
      result
      |> Map.take([
        :kind,
        :status,
        :intent,
        :action,
        :candidate_id,
        :record_uri,
        :reads,
        :effects,
        :skips,
        :errors
      ])
      |> Map.put(:completed_at, completed_at)

    state
    |> Map.put(:last_run, result)
    |> Map.put(:last_cycle, last_cycle)
  end

  defp candidate_id(%{id: id}), do: id
  defp candidate_id(_candidate), do: nil

  defp receipt_uri(%{receipt: receipt}), do: receipt_uri(receipt)
  defp receipt_uri(%{"receipt" => receipt}), do: receipt_uri(receipt)
  defp receipt_uri(%{uri: uri}) when is_binary(uri), do: uri
  defp receipt_uri(%{"uri" => uri}) when is_binary(uri), do: uri
  defp receipt_uri(_receipt), do: nil

  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(_reason), do: "operation_failed"

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
