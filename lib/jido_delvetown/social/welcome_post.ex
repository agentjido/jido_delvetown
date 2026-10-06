defmodule JidoDelvetown.WelcomePost do
  @moduledoc "Builds a verified, mention-aware welcome post."

  alias JidoDelvetown.{Candidate, Protocol}

  @facet_type "town.delve.richtext.facet"
  @mention_type "town.delve.richtext.facet#mention"
  @feed_limit 20
  @max_text_length 300
  @introduction_cues [
    "hello delvetown",
    "hello delve town",
    "hi delvetown",
    "hi delve town",
    "new here",
    "new to delvetown",
    "new to delve town",
    "first post",
    "introduce myself",
    "introduction"
  ]

  def prepare(%{author: author} = candidate, text) when is_map(author) do
    did = value(author, :did)
    handle = value(author, :handle)

    with {:ok, identity} <- resolve_identity(did, handle),
         {:ok, rendered_text} <- render_text(text, identity.handle) do
      {target, target_reads} = introduction_target(candidate, identity.did)

      candidate =
        candidate
        |> Map.put(:author, Map.merge(author, identity))
        |> put_target(target)

      {:ok, %{candidate: candidate, text: rendered_text, reads: 1 + target_reads}}
    end
  end

  def prepare(_candidate, _text), do: {:error, :welcome_identity_unresolved}

  def resolve_identity(did, handle) do
    with :ok <- validate_identity(did, handle),
         {:ok, response} <- Protocol.query("town.delve.actor.getProfile", %{actor: did}),
         profile when is_map(profile) <- profile(response),
         resolved_did when is_binary(resolved_did) <- value(profile, :did),
         resolved_handle when is_binary(resolved_handle) <- value(profile, :handle),
         :ok <- validate_identity(resolved_did, resolved_handle),
         true <- resolved_did == did,
         true <- normalize_handle(resolved_handle) == normalize_handle(handle) do
      {:ok, %{did: did, handle: normalize_handle(resolved_handle)}}
    else
      _reason -> {:error, :welcome_identity_unresolved}
    end
  end

  def render_text(text, handle) when is_binary(text) and is_binary(handle) do
    with :ok <- validate_handle(handle),
         body when body != "" <- String.trim(text) do
      mention = "@" <> normalize_handle(handle)

      rendered =
        if starts_with_mention?(body, mention) do
          body
        else
          mention <> " " <> body
        end

      {:ok, String.slice(rendered, 0, @max_text_length)}
    else
      _reason -> {:error, :invalid_welcome_text}
    end
  end

  def render_text(_text, _handle), do: {:error, :invalid_welcome_text}

  def record(text, did, handle, target \\ nil) do
    with :ok <- validate_identity(did, handle),
         true <- is_binary(text) and String.length(text) in 1..@max_text_length,
         {:ok, facet} <- mention_facet(text, handle, did),
         {:ok, reply} <- reply(target, did) do
      record = %{
        text: text,
        facets: [facet],
        langs: ["en"],
        created_at: Protocol.now()
      }

      {:ok, if(reply, do: Map.put(record, :reply, reply), else: record)}
    else
      _reason -> {:error, :invalid_welcome_record}
    end
  end

  def mention_facet(text, handle, did)
      when is_binary(text) and is_binary(handle) and is_binary(did) do
    mention = "@" <> normalize_handle(handle)

    with :ok <- validate_identity(did, handle),
         {byte_start, byte_length} <- :binary.match(text, mention) do
      {:ok,
       %{
         "$type" => @facet_type,
         index: %{byte_start: byte_start, byte_end: byte_start + byte_length},
         features: [%{"$type" => @mention_type, did: did}]
       }}
    else
      :nomatch -> {:error, :missing_welcome_mention}
      _reason -> {:error, :invalid_welcome_mention}
    end
  end

  def mention_facet(_text, _handle, _did), do: {:error, :invalid_welcome_mention}

  def safe_reply_target(target, did) when is_map(target) and is_binary(did) do
    root = value(target, :root, %{})
    uri = value(target, :uri)
    cid = value(target, :cid)
    root_uri = value(root, :uri)
    root_cid = value(root, :cid)

    if safe_post_uri?(uri, did) and safe_cid?(cid) and root_uri == uri and root_cid == cid do
      {:ok, %{uri: uri, cid: cid, root: %{uri: root_uri, cid: root_cid}}}
    else
      {:error, :invalid_welcome_target}
    end
  end

  def safe_reply_target(_target, _did), do: {:error, :invalid_welcome_target}

  def valid_identity?(did, handle), do: validate_identity(did, handle) == :ok

  def facet_type, do: @facet_type
  def mention_type, do: @mention_type

  defp introduction_target(%{reason: "new_member"}, did) do
    case Protocol.query("town.delve.feed.getAuthorFeed", %{actor: did, limit: @feed_limit}) do
      {:ok, response} ->
        target =
          response
          |> Candidate.posts()
          |> Enum.find(&eligible_introduction?(&1, did))

        {target, 1}

      {:error, _reason} ->
        {nil, 1}
    end
  end

  defp introduction_target(_candidate, _did), do: {nil, 0}

  defp eligible_introduction?(post, did) do
    get_in(post, [:author, :did]) == did and
      match?({:ok, _target}, safe_reply_target(post, did)) and
      introduction_text?(Map.get(post, :text))
  end

  defp introduction_text?(text) when is_binary(text) do
    normalized = String.downcase(text)
    Enum.any?(@introduction_cues, &String.contains?(normalized, &1))
  end

  defp introduction_text?(_text), do: false

  defp put_target(candidate, nil),
    do: candidate |> Map.put(:uri, nil) |> Map.put(:cid, nil) |> Map.put(:root, nil)

  defp put_target(candidate, target) do
    candidate
    |> Map.put(:uri, target.uri)
    |> Map.put(:cid, target.cid)
    |> Map.put(:root, target.root)
  end

  defp reply(nil, _did), do: {:ok, nil}

  defp reply(target, did) do
    with {:ok, target} <- safe_reply_target(target, did) do
      {:ok, %{root: target.root, parent: %{uri: target.uri, cid: target.cid}}}
    end
  end

  defp validate_identity(did, handle) do
    with :ok <- validate_did(did), :ok <- validate_handle(handle), do: :ok
  end

  defp validate_did(did) when is_binary(did) do
    if Regex.match?(~r/\Adid:[a-z0-9]+:[A-Za-z0-9._:%-]+(?::[A-Za-z0-9._:%-]+)*\z/, did),
      do: :ok,
      else: {:error, :invalid_did}
  end

  defp validate_did(_did), do: {:error, :invalid_did}

  defp validate_handle(handle) when is_binary(handle) do
    normalized = normalize_handle(handle)

    valid? =
      byte_size(normalized) <= 253 and
        Regex.match?(
          ~r/\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?\z/,
          normalized
        )

    if valid?, do: :ok, else: {:error, :invalid_handle}
  end

  defp validate_handle(_handle), do: {:error, :invalid_handle}

  defp safe_post_uri?(uri, did) when is_binary(uri) and is_binary(did) do
    Regex.match?(
      ~r/\Aat:\/\/#{Regex.escape(did)}\/town\.delve\.feed\.post\/[^\/\s]+\z/,
      uri
    )
  end

  defp safe_post_uri?(_uri, _did), do: false

  defp safe_cid?(cid) when is_binary(cid),
    do: cid != "" and Regex.match?(~r/\A[^\s\/]+\z/, cid)

  defp safe_cid?(_cid), do: false

  defp starts_with_mention?(text, mention) do
    text == mention or
      String.starts_with?(text, [mention <> " ", mention <> "\n", mention <> "\t"])
  end

  defp profile(response) when is_map(response), do: value(response, :profile, response)
  defp profile(_response), do: nil

  defp normalize_handle(handle), do: String.downcase(handle)

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
end
