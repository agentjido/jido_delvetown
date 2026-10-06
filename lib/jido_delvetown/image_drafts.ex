defmodule JidoDelvetown.ImageDrafts do
  @moduledoc """
  Durable image bytes and logical post drafts.

  Artifact identity is the SHA-256 digest of the exact image bytes. Draft
  identity is a caller-supplied stable key. Staging is idempotent for both.
  """

  alias JidoDelvetown.ImagePostContract
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{ImageArtifact, ImageDraft}

  @mime_types ~w(image/jpeg image/png image/webp image/gif image/avif)
  @max_dimension 16_384
  @max_caption_graphemes 300
  @max_caption_bytes 3_000
  @max_alt_graphemes 1_000
  @max_alt_bytes 10_000
  @max_draft_key_bytes 512

  @type stage_result :: %{
          draft: map(),
          artifact: map(),
          reused?: boolean(),
          artifact_reused?: boolean()
        }

  @spec stage(String.t(), binary(), map()) :: {:ok, stage_result()} | {:error, term()}
  def stage(draft_key, bytes, attrs)
      when is_binary(draft_key) and is_binary(bytes) and is_map(attrs) do
    with {:ok, staged} <- validate(draft_key, bytes, attrs) do
      Repo.transaction(fn -> stage_transaction(staged) end, mode: :immediate)
      |> transaction_result()
    end
  end

  def stage(_draft_key, _bytes, _attrs), do: {:error, :invalid_stage_request}

  @spec get(String.t()) :: map() | nil
  def get(draft_key) when is_binary(draft_key) do
    case Repo.get(ImageDraft, draft_key) do
      nil -> nil
      draft -> draft_view(draft, Repo.get!(ImageArtifact, draft.artifact_digest))
    end
  end

  def get(_draft_key), do: nil

  @spec get_artifact(String.t()) :: map() | nil
  def get_artifact(digest) when is_binary(digest) do
    digest
    |> then(&Repo.get(ImageArtifact, &1))
    |> artifact_view()
  end

  def get_artifact(_digest), do: nil

  @spec digest(binary()) :: String.t()
  def digest(bytes) when is_binary(bytes) do
    "sha256:" <> (:crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower))
  end

  @spec accepted_mime_types() :: [String.t()]
  def accepted_mime_types, do: @mime_types

  @spec max_dimension() :: pos_integer()
  def max_dimension, do: @max_dimension

  defp validate(draft_key, bytes, attrs) do
    caption = value(attrs, :caption)
    alt_text = value(attrs, :alt_text)
    mime_type = value(attrs, :mime_type)
    width = value(attrs, :width)
    height = value(attrs, :height)
    source_metadata = value(attrs, :source_metadata, %{})

    with :ok <- validate_draft_key(draft_key),
         :ok <- validate_bytes(bytes),
         :ok <- validate_mime_type(mime_type),
         :ok <- validate_dimensions(width, height),
         :ok <- validate_text(caption, :caption),
         :ok <- validate_text(alt_text, :alt_text),
         {:ok, source_metadata} <- normalize_metadata(source_metadata) do
      {:ok,
       %{
         draft_key: draft_key,
         bytes: bytes,
         digest: digest(bytes),
         byte_size: byte_size(bytes),
         mime_type: mime_type,
         width: width,
         height: height,
         caption: caption,
         alt_text: alt_text,
         source_metadata: source_metadata
       }}
    end
  end

  defp validate_draft_key(draft_key) do
    if String.valid?(draft_key) and String.trim(draft_key) != "" and
         byte_size(draft_key) <= @max_draft_key_bytes,
       do: :ok,
       else: {:error, :invalid_draft_key}
  end

  defp validate_bytes(bytes) do
    size = byte_size(bytes)

    cond do
      size == 0 -> {:error, :empty_image}
      size > ImagePostContract.max_blob_bytes() -> {:error, :image_too_large}
      true -> :ok
    end
  end

  defp validate_mime_type(mime_type) when mime_type in @mime_types, do: :ok
  defp validate_mime_type(_mime_type), do: {:error, :unsupported_mime_type}

  defp validate_dimensions(nil, nil), do: :ok

  defp validate_dimensions(width, height)
       when is_integer(width) and width in 1..@max_dimension and is_integer(height) and
              height in 1..@max_dimension,
       do: :ok

  defp validate_dimensions(_width, _height), do: {:error, :invalid_dimensions}

  defp validate_text(value, :caption) do
    validate_required_text(
      value,
      @max_caption_graphemes,
      @max_caption_bytes,
      :invalid_caption,
      :caption_too_long
    )
  end

  defp validate_text(value, :alt_text) do
    validate_required_text(
      value,
      @max_alt_graphemes,
      @max_alt_bytes,
      :invalid_alt_text,
      :alt_text_too_long
    )
  end

  defp validate_required_text(value, max_graphemes, max_bytes, invalid, too_long)
       when is_binary(value) do
    cond do
      not String.valid?(value) -> {:error, invalid}
      String.trim(value) == "" -> {:error, invalid}
      String.length(value) > max_graphemes -> {:error, too_long}
      byte_size(value) > max_bytes -> {:error, too_long}
      true -> :ok
    end
  end

  defp validate_required_text(_value, _max_graphemes, _max_bytes, invalid, _too_long),
    do: {:error, invalid}

  defp normalize_metadata(metadata) when is_map(metadata) do
    normalized = json_safe(metadata)

    case Jason.encode(normalized) do
      {:ok, _json} -> {:ok, normalized}
      {:error, _reason} -> {:error, :invalid_source_metadata}
    end
  end

  defp normalize_metadata(_metadata), do: {:error, :invalid_source_metadata}

  defp stage_transaction(staged) do
    {artifact, artifact_reused?} = stage_artifact(staged)

    case Repo.get(ImageDraft, staged.draft_key) do
      nil ->
        draft =
          %ImageDraft{
            draft_key: staged.draft_key,
            artifact_digest: staged.digest,
            caption: staged.caption,
            alt_text: staged.alt_text,
            state: "staged"
          }
          |> Repo.insert!()

        stage_result(draft, artifact, false, artifact_reused?)

      draft ->
        validate_existing_draft(draft, staged)
        stage_result(draft, artifact, true, artifact_reused?)
    end
  end

  defp stage_artifact(staged) do
    case Repo.get(ImageArtifact, staged.digest) do
      nil ->
        artifact =
          %ImageArtifact{
            digest: staged.digest,
            bytes: staged.bytes,
            mime_type: staged.mime_type,
            byte_size: staged.byte_size,
            width: staged.width,
            height: staged.height,
            source_metadata: staged.source_metadata,
            state: "staged"
          }
          |> Repo.insert!()

        {artifact, false}

      artifact ->
        artifact = validate_existing_artifact(artifact, staged)
        {artifact, true}
    end
  end

  defp validate_existing_artifact(artifact, staged) do
    cond do
      artifact.byte_size != staged.byte_size ->
        Repo.rollback({:artifact_conflict, :byte_size})

      artifact.mime_type != staged.mime_type ->
        Repo.rollback({:artifact_conflict, :mime_type})

      conflicting_dimension?(artifact.width, staged.width) ->
        Repo.rollback({:artifact_conflict, :width})

      conflicting_dimension?(artifact.height, staged.height) ->
        Repo.rollback({:artifact_conflict, :height})

      is_nil(artifact.width) and is_integer(staged.width) ->
        artifact
        |> Ecto.Changeset.change(width: staged.width, height: staged.height)
        |> Repo.update!()

      true ->
        artifact
    end
  end

  defp conflicting_dimension?(nil, _new), do: false
  defp conflicting_dimension?(_stored, nil), do: false
  defp conflicting_dimension?(stored, new), do: stored != new

  defp validate_existing_draft(draft, staged) do
    cond do
      draft.artifact_digest != staged.digest ->
        Repo.rollback({:draft_conflict, :artifact})

      draft.caption != staged.caption ->
        Repo.rollback({:draft_conflict, :caption})

      draft.alt_text != staged.alt_text ->
        Repo.rollback({:draft_conflict, :alt_text})

      true ->
        :ok
    end
  end

  defp stage_result(draft, artifact, reused?, artifact_reused?) do
    %{
      draft: draft_view(draft, artifact),
      artifact: artifact_view(artifact),
      reused?: reused?,
      artifact_reused?: artifact_reused?
    }
  end

  defp draft_view(draft, artifact) do
    %{
      key: draft.draft_key,
      artifact_digest: draft.artifact_digest,
      caption: draft.caption,
      alt_text: draft.alt_text,
      state: draft.state,
      failure: draft.failure,
      inserted_at: draft.inserted_at,
      updated_at: draft.updated_at,
      artifact: artifact_view(artifact)
    }
  end

  defp artifact_view(nil), do: nil

  defp artifact_view(artifact) do
    %{
      digest: artifact.digest,
      bytes: artifact.bytes,
      mime_type: artifact.mime_type,
      byte_size: artifact.byte_size,
      width: artifact.width,
      height: artifact.height,
      source_metadata: artifact.source_metadata,
      state: artifact.state,
      failure: artifact.failure,
      inserted_at: artifact.inserted_at,
      updated_at: artifact.updated_at
    }
  end

  defp transaction_result({:ok, value}), do: {:ok, value}
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp json_safe(nil), do: nil
  defp json_safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%_{} = value), do: value |> Map.from_struct() |> json_safe()
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_safe(item)} end)
  end

  defp json_safe(value), do: inspect(value)
end
