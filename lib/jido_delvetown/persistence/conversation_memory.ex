defmodule JidoDelvetown.ConversationMemory do
  @moduledoc "Owns durable conversation turns, status, and response context."

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.Conversation

  @closing_reasons [
    "actor_opt_out",
    "conversation_closed",
    "conversation_turn_limit",
    "conversation_too_old",
    "conversation_non_response_limit"
  ]

  def get(root_uri, opts \\ []), do: repo(opts).get(Conversation, root_uri)

  def remember(candidate, cycle, decision, at, opts \\ [])

  def remember(candidate, %{status: status}, %{action: "reply"}, at, opts)
      when status in ["acted", "simulated"] do
    root_uri = get_in(candidate, [:root, :uri])

    if is_binary(root_uri) do
      repo = repo(opts)
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

  def remember(candidate, %{reason: reason}, _decision, _at, opts)
      when reason in @closing_reasons do
    root_uri = get_in(candidate, [:root, :uri])
    repo = repo(opts)

    case if(is_binary(root_uri), do: repo.get(Conversation, root_uri)) do
      nil ->
        :ok

      conversation ->
        conversation
        |> Ecto.Changeset.change(status: "closed")
        |> repo.update()
        |> case do
          {:ok, _conversation} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def remember(_candidate, _cycle, _decision, _at, _opts), do: :ok

  def context(root_uri, opts \\ [])

  def context(root_uri, opts) when is_binary(root_uri) do
    root_uri
    |> get(opts)
    |> conversation_context()
  end

  def context(_root_uri, _opts), do: nil

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

  defp transaction_ok({:ok, _value}), do: :ok
  defp transaction_ok({:error, reason}), do: {:error, reason}

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp repo(opts), do: Keyword.get(opts, :repo, Repo)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
