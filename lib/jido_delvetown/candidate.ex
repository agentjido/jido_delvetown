defmodule JidoDelvetown.Candidate do
  @moduledoc false

  @text_limit 500
  @reply_limit 4

  def notifications(response) do
    response
    |> value(:notifications, [])
    |> Enum.map(&notification/1)
    |> Enum.reject(&is_nil(&1.id))
  end

  def posts(response) do
    response
    |> value(:feed, [])
    |> Enum.map(&post/1)
    |> Enum.reject(&is_nil(&1.id))
  end

  def notification(item) when is_map(item) do
    record = value(item, :record, %{})
    uri = value(item, :uri)
    cid = value(item, :cid)

    %{
      id: uri || value(item, :reason_subject),
      uri: uri,
      cid: cid,
      reason: item |> value(:reason, "unknown") |> to_string(),
      unread?: value(item, :is_read) not in [true, "true"],
      indexed_at: value(item, :indexed_at),
      author: actor(value(item, :author, %{})),
      text: record |> value(:text, "") |> text(),
      parent: strong_ref(%{uri: uri, cid: cid}),
      root: reply_root(record) || strong_ref(%{uri: uri, cid: cid})
    }
  end

  def post(item) when is_map(item) do
    view = value(item, :post, item)
    record = value(view, :record, value(view, :value, %{}))
    uri = value(view, :uri)
    cid = value(view, :cid)

    %{
      id: uri,
      uri: uri,
      cid: cid,
      indexed_at: value(view, :indexed_at),
      author: actor(value(view, :author, %{})),
      text: record |> value(:text, "") |> text(),
      parent: strong_ref(%{uri: uri, cid: cid}),
      root: reply_root(record) || strong_ref(%{uri: uri, cid: cid})
    }
  end

  def thread(response) when is_map(response) do
    response
    |> value(:thread, response)
    |> thread_node(0)
  end

  def membership(response) when is_map(response) do
    %{
      active: value(response, :active),
      status: value(response, :status),
      role: value(response, :role),
      joined_at: value(response, :joined_at)
    }
    |> reject_nil()
  end

  def question?(%{text: text}) when is_binary(text), do: String.contains?(text, "?")
  def question?(_candidate), do: false

  defp thread_node(_node, depth) when depth > 2, do: nil

  defp thread_node(node, depth) when is_map(node) do
    post = post(value(node, :post, node))

    %{
      post: post,
      parent: maybe_thread_node(value(node, :parent), depth + 1),
      replies:
        node
        |> value(:replies, [])
        |> Enum.take(@reply_limit)
        |> Enum.map(&thread_node(&1, depth + 1))
        |> Enum.reject(&is_nil/1)
    }
    |> reject_nil()
  end

  defp thread_node(_node, _depth), do: nil

  defp maybe_thread_node(nil, _depth), do: nil
  defp maybe_thread_node(node, depth), do: thread_node(node, depth)

  defp actor(actor) when is_map(actor) do
    %{
      did: value(actor, :did),
      handle: value(actor, :handle),
      display_name: value(actor, :display_name)
    }
    |> reject_nil()
  end

  defp actor(_actor), do: %{}

  defp reply_root(record) do
    record
    |> value(:reply, %{})
    |> value(:root)
    |> strong_ref()
  end

  defp strong_ref(ref) when is_map(ref) do
    case {value(ref, :uri), value(ref, :cid)} do
      {uri, cid} when is_binary(uri) and is_binary(cid) -> %{uri: uri, cid: cid}
      _invalid -> nil
    end
  end

  defp strong_ref(_ref), do: nil

  defp text(value) when is_binary(value), do: String.slice(value, 0, @text_limit)
  defp text(_value), do: ""

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map) do
    string = Atom.to_string(key)
    camel = Regex.replace(~r/_([a-z])/, string, fn _, letter -> String.upcase(letter) end)

    Enum.reduce_while([key, string, camel], default, fn candidate, _acc ->
      case Map.fetch(map, candidate) do
        {:ok, result} -> {:halt, result}
        :error -> {:cont, default}
      end
    end)
  end

  defp value(_map, _key, default), do: default

  defp reject_nil(map), do: Map.reject(map, fn {_key, item} -> is_nil(item) end)
end
