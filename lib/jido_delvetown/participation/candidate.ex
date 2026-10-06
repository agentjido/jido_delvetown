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

  def members(response) do
    response
    |> value(:actors, [])
    |> Enum.map(&member/1)
    |> Enum.reject(&is_nil(&1.id))
  end

  def member(item) when is_map(item) do
    author = member_actor(item)
    did = Map.get(author, :did)
    indexed_at = value(item, :created_at) || value(item, :indexed_at)

    %{
      id: did,
      event_key: JidoDelvetown.InteractionEvents.event_key("new_member", [did]),
      protocol_id: did,
      uri: nil,
      cid: nil,
      reason: "new_member",
      raw_reason: "new_member",
      reason_subject: nil,
      unread?: true,
      indexed_at: indexed_at,
      joined_at: indexed_at,
      author: author,
      text: item |> value(:description, "") |> text(),
      parent: nil,
      root: nil
    }
  end

  def notification(item) when is_map(item) do
    record = value(item, :record, %{})
    uri = value(item, :uri)
    cid = value(item, :cid)
    protocol_id = present(value(item, :id)) || present(value(item, :notification_id))
    reason_subject = value(item, :reason_subject)
    raw_reason = item |> value(:reason, "unknown") |> to_string()
    reason = normalize_reason(raw_reason)
    author = actor(value(item, :author, %{}))
    indexed_at = value(item, :indexed_at)
    target = record |> value(:subject, %{}) |> strong_ref()
    target_uri = target_uri(target, reason_subject)

    event_key =
      notification_event_key(protocol_id, reason, author, uri, reason_subject, indexed_at)

    %{
      id: protocol_id || uri || reason_subject || event_key,
      event_key: event_key,
      protocol_id: protocol_id,
      uri: uri,
      cid: cid,
      reason: reason,
      raw_reason: raw_reason,
      reason_subject: reason_subject,
      target_uri: target_uri,
      target_cid: target && target.cid,
      unread?: value(item, :is_read) not in [true, "true"],
      indexed_at: indexed_at,
      author: author,
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
      viewer: value(view, :viewer, %{}) |> post_viewer() |> non_empty(),
      labels: value(view, :labels, []) |> label_values() |> non_empty(),
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
      display_name: value(actor, :display_name),
      viewer: actor |> value(:viewer, %{}) |> actor_viewer() |> non_empty(),
      labels: actor |> value(:labels, []) |> label_values() |> non_empty()
    }
    |> reject_nil()
  end

  defp actor(_actor), do: %{}

  defp member_actor(actor) when is_map(actor) do
    %{
      did: value(actor, :did),
      handle: value(actor, :handle),
      display_name: value(actor, :display_name),
      description: actor |> value(:description, "") |> text(),
      created_at: value(actor, :created_at),
      indexed_at: value(actor, :indexed_at)
    }
    |> reject_nil()
  end

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

  defp post_viewer(viewer) when is_map(viewer) do
    %{
      like: value(viewer, :like),
      repost: value(viewer, :repost),
      thread_muted: value(viewer, :thread_muted),
      embedding_disabled: value(viewer, :embedding_disabled)
    }
    |> reject_nil()
  end

  defp post_viewer(_viewer), do: %{}

  defp actor_viewer(viewer) when is_map(viewer) do
    %{
      blocked_by: value(viewer, :blocked_by),
      blocking: value(viewer, :blocking),
      muted: value(viewer, :muted)
    }
    |> reject_nil()
  end

  defp actor_viewer(_viewer), do: %{}

  defp label_values(labels) when is_list(labels) do
    labels
    |> Enum.map(fn
      label when is_binary(label) -> label
      label when is_map(label) -> value(label, :val)
      _label -> nil
    end)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp label_values(_labels), do: []

  defp non_empty(value) when value in [%{}, []], do: nil
  defp non_empty(value), do: value

  defp text(value) when is_binary(value), do: String.slice(value, 0, @text_limit)
  defp text(_value), do: ""

  defp notification_event_key(protocol_id, _reason, _author, _uri, _subject, _indexed_at)
       when is_binary(protocol_id) and protocol_id != "",
       do: "notification:" <> protocol_id

  defp notification_event_key(_protocol_id, reason, author, uri, subject, indexed_at) do
    JidoDelvetown.InteractionEvents.event_key("notification", [
      reason,
      Map.get(author, :did, ""),
      uri || subject || "",
      indexed_at || ""
    ])
  end

  defp normalize_reason(reason) do
    case String.downcase(reason) do
      value when value in ["reply", "replied"] -> "reply"
      value when value in ["mention", "mentioned"] -> "mention"
      value when value in ["follow", "followed", "new_follow"] -> "follow"
      value when value in ["like", "liked"] -> "like"
      _value -> "unknown"
    end
  end

  defp target_uri(%{uri: uri}, _reason_subject), do: uri
  defp target_uri(_target, reason_subject) when is_binary(reason_subject), do: reason_subject
  defp target_uri(_target, _reason_subject), do: nil

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil

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
