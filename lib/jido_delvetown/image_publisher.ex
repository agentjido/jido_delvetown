defmodule JidoDelvetown.ImagePublisher do
  @moduledoc """
  Publishes one staged image draft as a top-level DelveTown post.

  The exact post record and stable effect key are saved before the remote
  write. A retry therefore uses the same record key and record body.
  """

  alias JidoDelvetown.ImageDrafts
  alias JidoDelvetown.ImagePostContract
  alias JidoDelvetown.ImageUploader
  alias JidoDelvetown.Protocol

  @collection "town.delve.feed.post"
  @default_langs ["en"]

  @spec publish(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def publish(draft_key, opts \\ [])

  def publish(draft_key, opts) when is_binary(draft_key) and is_list(opts) do
    with :ok <- Protocol.ensure_writes_enabled(),
         {:ok, publish_opts} <- publication_options(opts),
         {:ok, draft} <- fetch_draft(draft_key),
         {:ok, upload} <- ImageUploader.upload(draft.artifact_digest),
         {:ok, record} <- build_record(draft, upload.blob, publish_opts),
         effect_key = Protocol.effect_key("image_post", [draft_key]),
         {:ok, reservation} <-
           ImageDrafts.reserve_publication(draft_key, effect_key, record) do
      publish_or_reuse(draft_key, effect_key, reservation)
    end
  end

  def publish(_draft_key, _opts), do: {:error, :invalid_image_publication_request}

  @doc false
  @spec build_record(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def build_record(draft, blob, opts) when is_map(draft) and is_map(blob) and is_list(opts) do
    with {:ok, publish_opts} <- publication_options(opts) do
      langs = Keyword.fetch!(publish_opts, :langs)
      created_at = Keyword.fetch!(publish_opts, :created_at)

      image =
        %{"image" => blob, "alt" => draft.alt_text}
        |> put_aspect_ratio(draft.artifact)

      record = %{
        "$type" => ImagePostContract.post_type(),
        "text" => draft.caption,
        "langs" => langs,
        "createdAt" => created_at,
        "embed" => %{
          "$type" => ImagePostContract.embed_type(),
          "images" => [image]
        }
      }

      case ImagePostContract.validate(record) do
        :ok -> {:ok, record}
        {:error, reason} -> {:error, {:invalid_image_post, reason}}
      end
    end
  end

  def build_record(_draft, _blob, _opts), do: {:error, :invalid_image_post}

  defp publish_or_reuse(_draft_key, _effect_key, %{reused?: true, draft: draft, record: record}) do
    {:ok,
     %{
       draft: draft,
       record: record,
       receipt: draft.post_receipt,
       reused?: true,
       reconciled?: false
     }}
  end

  defp publish_or_reuse(draft_key, effect_key, %{reused?: false, record: record}) do
    case Protocol.create_record(effect_key, @collection, record, subject_key: draft_key) do
      {:ok, result} -> complete_publication(draft_key, effect_key, record, result)
      {:error, reason} -> fail_publication(draft_key, effect_key, reason)
    end
  end

  defp complete_publication(draft_key, effect_key, record, result) do
    with {:ok, draft} <-
           ImageDrafts.complete_publication(draft_key, effect_key, result.receipt) do
      {:ok,
       %{
         draft: draft,
         record: record,
         receipt: draft.post_receipt,
         reused?: result.reused?,
         reconciled?: result.reconciled?
       }}
    end
  end

  defp fail_publication(draft_key, effect_key, reason) do
    failure = %{operation: "image_post", reason: safe_reason(reason)}

    case ImageDrafts.record_publication_failure(draft_key, effect_key, failure) do
      {:ok, _draft} -> {:error, reason}
      {:error, save_error} -> {:error, {:image_publication_failure_not_saved, reason, save_error}}
    end
  end

  defp fetch_draft(draft_key) do
    case ImageDrafts.get(draft_key) do
      nil -> {:error, :image_draft_not_found}
      draft -> {:ok, draft}
    end
  end

  defp put_aspect_ratio(image, %{width: width, height: height})
       when is_integer(width) and is_integer(height) do
    Map.put(image, "aspectRatio", %{"width" => width, "height" => height})
  end

  defp put_aspect_ratio(image, _artifact), do: image

  defp publication_options(opts) do
    langs = Keyword.get(opts, :langs, @default_langs)
    created_at = Keyword.get_lazy(opts, :created_at, &Protocol.now/0)

    with :ok <- validate_langs(langs),
         :ok <- validate_created_at(created_at) do
      {:ok, [langs: langs, created_at: created_at]}
    end
  end

  defp validate_langs(langs) when is_list(langs) and length(langs) <= 3 do
    if Enum.all?(langs, &(is_binary(&1) and String.trim(&1) != "")),
      do: :ok,
      else: {:error, :invalid_languages}
  end

  defp validate_langs(_langs), do: {:error, :invalid_languages}

  defp validate_created_at(created_at) when is_binary(created_at) do
    case DateTime.from_iso8601(created_at) do
      {:ok, _datetime, _offset} -> :ok
      {:error, _reason} -> {:error, :invalid_created_at}
    end
  end

  defp validate_created_at(_created_at), do: {:error, :invalid_created_at}

  defp safe_reason(%ProtoRune.XRPC.Error{} = error) do
    Map.take(error, [:reason, :message, :http_status, :retry_after])
  end

  defp safe_reason(reason) when is_atom(reason) or is_binary(reason) or is_map(reason),
    do: reason

  defp safe_reason(reason), do: inspect(reason)
end
