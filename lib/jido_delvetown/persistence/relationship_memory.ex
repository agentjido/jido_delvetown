defmodule JidoDelvetown.RelationshipMemory do
  @moduledoc "Owns durable follow and friend-reference updates."

  alias JidoDelvetown.FriendList

  def remember(candidate, cycle, decision, at) do
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
end
