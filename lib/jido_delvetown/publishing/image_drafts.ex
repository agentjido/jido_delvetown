defmodule JidoDelvetown.ImageDrafts do
  @moduledoc """
  Durable image bytes and logical post drafts.

  Artifact identity is the SHA-256 digest of the exact image bytes. Draft
  identity is a caller-supplied stable key. Staging is idempotent for both.
  """

  alias JidoDelvetown.ImagePostContract
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings
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

  @doc false
  @spec begin_upload(String.t()) ::
          {:ok, %{artifact: map(), reused?: boolean()}} | {:error, term()}
  def begin_upload(digest) when is_binary(digest) do
    Repo.transaction(fn -> begin_upload_transaction(digest) end, mode: :immediate)
    |> transaction_result()
  end

  def begin_upload(_digest), do: {:error, :invalid_artifact_digest}

  @doc false
  @spec complete_upload(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def complete_upload(digest, blob) when is_binary(digest) and is_map(blob) do
    Repo.transaction(fn -> complete_upload_transaction(digest, blob) end, mode: :immediate)
    |> transaction_result()
  end

  def complete_upload(_digest, _blob), do: {:error, :invalid_upload_receipt}

  @doc false
  @spec record_upload_failure(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def record_upload_failure(digest, failure) when is_binary(digest) and is_map(failure) do
    with {:ok, failure} <- normalize_metadata(failure) do
      Repo.transaction(fn -> record_upload_failure_transaction(digest, failure) end,
        mode: :immediate
      )
      |> transaction_result()
    end
  end

  def record_upload_failure(_digest, _failure), do: {:error, :invalid_upload_failure}

  @doc false
  @spec reserve_publication(String.t(), String.t(), map(), map()) ::
          {:ok, %{draft: map(), record: map(), reused?: boolean()}} | {:error, term()}
  def reserve_publication(draft_key, effect_key, record, settings)
      when is_binary(draft_key) and is_binary(effect_key) and is_map(record) and
             is_map(settings) do
    with {:ok, settings} <- Settings.reference(settings) do
      Repo.transaction(
        fn -> reserve_publication_transaction(draft_key, effect_key, record, settings) end,
        mode: :immediate
      )
      |> transaction_result()
    end
  end

  def reserve_publication(_draft_key, _effect_key, _record, _settings),
    do: {:error, :invalid_publication_request}

  @doc false
  @spec complete_publication(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def complete_publication(draft_key, effect_key, receipt)
      when is_binary(draft_key) and is_binary(effect_key) and is_map(receipt) do
    Repo.transaction(
      fn -> complete_publication_transaction(draft_key, effect_key, receipt) end,
      mode: :immediate
    )
    |> transaction_result()
  end

  def complete_publication(_draft_key, _effect_key, _receipt),
    do: {:error, :invalid_post_receipt}

  @doc false
  @spec record_publication_failure(String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def record_publication_failure(draft_key, effect_key, failure)
      when is_binary(draft_key) and is_binary(effect_key) and is_map(failure) do
    with {:ok, failure} <- normalize_metadata(failure) do
      Repo.transaction(
        fn -> record_publication_failure_transaction(draft_key, effect_key, failure) end,
        mode: :immediate
      )
      |> transaction_result()
    end
  end

  def record_publication_failure(_draft_key, _effect_key, _failure),
    do: {:error, :invalid_publication_failure}

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

  defp begin_upload_transaction(digest) do
    case Repo.get(ImageArtifact, digest) do
      nil ->
        Repo.rollback(:artifact_not_found)

      artifact ->
        case validate_stored_artifact(artifact) do
          :ok -> begin_valid_upload(artifact)
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp begin_valid_upload(%{state: "uploaded", upload_receipt: receipt} = artifact)
       when is_map(receipt) do
    %{artifact: artifact_view(artifact), reused?: true}
  end

  defp begin_valid_upload(%{state: state} = artifact)
       when state in ["staged", "upload_uncertain"] do
    now = DateTime.utc_now()

    artifact =
      artifact
      |> Ecto.Changeset.change(
        state: "upload_uncertain",
        failure: nil,
        upload_attempt_count: artifact.upload_attempt_count + 1,
        upload_started_at: now
      )
      |> Repo.update!()

    %{artifact: artifact_view(artifact), reused?: false}
  end

  defp begin_valid_upload(%{state: "uploaded"}), do: Repo.rollback(:missing_upload_receipt)

  defp begin_valid_upload(%{state: state}),
    do: Repo.rollback({:invalid_artifact_state, state})

  defp complete_upload_transaction(digest, blob) do
    case Repo.get(ImageArtifact, digest) do
      nil ->
        Repo.rollback(:artifact_not_found)

      artifact ->
        with :ok <- validate_upload_receipt(blob, artifact) do
          receipt = canonical_blob_receipt(blob)
          persist_upload_receipt(artifact, receipt)
        else
          {:error, reason} -> Repo.rollback({:invalid_upload_receipt, reason})
        end
    end
  end

  defp persist_upload_receipt(%{state: "uploaded", upload_receipt: receipt} = artifact, receipt),
    do: artifact_view(artifact)

  defp persist_upload_receipt(%{state: "uploaded"}, _receipt),
    do: Repo.rollback(:upload_receipt_conflict)

  defp persist_upload_receipt(%{state: "upload_uncertain"} = artifact, receipt) do
    artifact
    |> Ecto.Changeset.change(
      state: "uploaded",
      failure: nil,
      upload_receipt: receipt,
      uploaded_at: DateTime.utc_now()
    )
    |> Repo.update!()
    |> artifact_view()
  end

  defp persist_upload_receipt(%{state: state}, _receipt),
    do: Repo.rollback({:invalid_artifact_state, state})

  defp record_upload_failure_transaction(digest, failure) do
    case Repo.get(ImageArtifact, digest) do
      nil ->
        Repo.rollback(:artifact_not_found)

      %{state: "upload_uncertain"} = artifact ->
        artifact
        |> Ecto.Changeset.change(failure: failure)
        |> Repo.update!()
        |> artifact_view()

      %{state: state} ->
        Repo.rollback({:invalid_artifact_state, state})
    end
  end

  defp reserve_publication_transaction(draft_key, effect_key, candidate_record, settings) do
    case Repo.get(ImageDraft, draft_key) do
      nil ->
        Repo.rollback(:image_draft_not_found)

      draft ->
        artifact = Repo.get!(ImageArtifact, draft.artifact_digest)
        reserve_valid_publication(draft, artifact, effect_key, candidate_record, settings)
    end
  end

  defp reserve_valid_publication(draft, artifact, effect_key, candidate_record, settings) do
    record = draft.post_record || json_safe(candidate_record)
    publication_settings = draft.publication_settings || json_safe(settings)

    with :ok <- validate_publication_effect_key(draft, effect_key),
         :ok <- validate_publication_artifact(artifact),
         :ok <- validate_publication_record(record, draft, artifact) do
      reserve_publication_state(
        draft,
        artifact,
        effect_key,
        record,
        publication_settings
      )
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp reserve_publication_state(
         %{state: "published", post_receipt: receipt} = draft,
         artifact,
         _effect_key,
         record,
         _settings
       )
       when is_map(receipt) do
    %{draft: draft_view(draft, artifact), record: record, reused?: true}
  end

  defp reserve_publication_state(
         %{state: "published"},
         _artifact,
         _effect_key,
         _record,
         _settings
       ),
       do: Repo.rollback(:missing_post_receipt)

  defp reserve_publication_state(
         %{state: state} = draft,
         artifact,
         effect_key,
         record,
         settings
       )
       when state in ["staged", "publish_uncertain"] do
    draft =
      draft
      |> Ecto.Changeset.change(
        state: "publish_uncertain",
        failure: nil,
        publication_settings: settings,
        post_effect_key: effect_key,
        post_record: record,
        publish_started_at: DateTime.utc_now()
      )
      |> Repo.update!()

    %{draft: draft_view(draft, artifact), record: record, reused?: false}
  end

  defp reserve_publication_state(%{state: state}, _artifact, _effect_key, _record, _settings),
    do: Repo.rollback({:invalid_draft_state, state})

  defp complete_publication_transaction(draft_key, effect_key, receipt) do
    case Repo.get(ImageDraft, draft_key) do
      nil ->
        Repo.rollback(:image_draft_not_found)

      draft ->
        artifact = Repo.get!(ImageArtifact, draft.artifact_digest)

        with :ok <- validate_publication_effect_key(draft, effect_key),
             :ok <- validate_post_receipt(receipt),
             {:ok, receipt} <- normalize_metadata(receipt) do
          persist_post_receipt(draft, artifact, receipt)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp persist_post_receipt(
         %{state: "published", post_receipt: receipt} = draft,
         artifact,
         receipt
       ),
       do: draft_view(draft, artifact)

  defp persist_post_receipt(%{state: "published"}, _artifact, _receipt),
    do: Repo.rollback(:post_receipt_conflict)

  defp persist_post_receipt(%{state: "publish_uncertain"} = draft, artifact, receipt) do
    draft
    |> Ecto.Changeset.change(
      state: "published",
      failure: nil,
      post_receipt: receipt,
      published_at: DateTime.utc_now()
    )
    |> Repo.update!()
    |> draft_view(artifact)
  end

  defp persist_post_receipt(%{state: state}, _artifact, _receipt),
    do: Repo.rollback({:invalid_draft_state, state})

  defp record_publication_failure_transaction(draft_key, effect_key, failure) do
    case Repo.get(ImageDraft, draft_key) do
      nil ->
        Repo.rollback(:image_draft_not_found)

      %{state: "publish_uncertain", post_effect_key: ^effect_key} = draft ->
        artifact = Repo.get!(ImageArtifact, draft.artifact_digest)

        draft
        |> Ecto.Changeset.change(failure: failure)
        |> Repo.update!()
        |> draft_view(artifact)

      %{post_effect_key: stored_key} when stored_key != effect_key ->
        Repo.rollback(:publication_effect_conflict)

      %{state: state} ->
        Repo.rollback({:invalid_draft_state, state})
    end
  end

  defp validate_publication_effect_key(%{post_effect_key: nil}, _effect_key), do: :ok
  defp validate_publication_effect_key(%{post_effect_key: effect_key}, effect_key), do: :ok

  defp validate_publication_effect_key(_draft, _effect_key),
    do: {:error, :publication_effect_conflict}

  defp validate_publication_artifact(%{state: "uploaded", upload_receipt: receipt})
       when is_map(receipt),
       do: :ok

  defp validate_publication_artifact(_artifact), do: {:error, :artifact_not_uploaded}

  defp validate_publication_record(record, draft, artifact) do
    with :ok <- ImagePostContract.validate(record),
         true <- value(record, :text) == draft.caption,
         [image] <- record |> value(:embed, %{}) |> value(:images, []),
         true <- value(image, :alt) == draft.alt_text,
         true <- value(image, :image) == artifact.upload_receipt,
         :ok <-
           validate_publication_aspect_ratio(
             blob_value(image, :aspect_ratio, "aspectRatio"),
             artifact
           ) do
      :ok
    else
      _other -> {:error, :publication_record_mismatch}
    end
  end

  defp validate_publication_aspect_ratio(nil, %{width: nil, height: nil}), do: :ok

  defp validate_publication_aspect_ratio(ratio, %{width: width, height: height})
       when is_map(ratio) and is_integer(width) and is_integer(height) do
    if value(ratio, :width) == width and value(ratio, :height) == height,
      do: :ok,
      else: {:error, :publication_record_mismatch}
  end

  defp validate_publication_aspect_ratio(_ratio, _artifact),
    do: {:error, :publication_record_mismatch}

  defp validate_post_receipt(receipt) do
    if is_binary(value(receipt, :uri)) and is_binary(value(receipt, :cid)),
      do: :ok,
      else: {:error, :invalid_post_receipt}
  end

  defp validate_stored_artifact(artifact) do
    cond do
      not is_binary(artifact.bytes) or byte_size(artifact.bytes) == 0 ->
        {:error, :invalid_staged_bytes}

      artifact.byte_size != byte_size(artifact.bytes) ->
        {:error, :artifact_size_mismatch}

      artifact.digest != digest(artifact.bytes) ->
        {:error, :artifact_digest_mismatch}

      artifact.mime_type not in @mime_types ->
        {:error, :unsupported_mime_type}

      artifact.byte_size > ImagePostContract.max_blob_bytes() ->
        {:error, :image_too_large}

      true ->
        :ok
    end
  end

  defp validate_upload_receipt(blob, artifact) do
    with :ok <- ImagePostContract.validate_blob(blob),
         true <- blob_value(blob, :mime_type, "mimeType") == artifact.mime_type,
         true <- blob_value(blob, :size, "size") == artifact.byte_size do
      :ok
    else
      false -> {:error, :artifact_metadata_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp canonical_blob_receipt(blob) do
    ref = blob_value(blob, :ref, "ref")

    %{
      "$type" => blob_value(blob, :"$type", "$type"),
      "ref" => %{"$link" => blob_value(ref, :"$link", "$link")},
      "mimeType" => blob_value(blob, :mime_type, "mimeType"),
      "size" => blob_value(blob, :size, "size")
    }
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
      publication_settings: draft.publication_settings,
      post_effect_key: draft.post_effect_key,
      post_record: draft.post_record,
      post_receipt: draft.post_receipt,
      publish_started_at: draft.publish_started_at,
      published_at: draft.published_at,
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
      upload_attempt_count: artifact.upload_attempt_count,
      upload_receipt: artifact.upload_receipt,
      upload_started_at: artifact.upload_started_at,
      uploaded_at: artifact.uploaded_at,
      inserted_at: artifact.inserted_at,
      updated_at: artifact.updated_at
    }
  end

  defp transaction_result({:ok, value}), do: {:ok, value}
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp blob_value(map, atom_key, string_key) do
    case Map.fetch(map, atom_key) do
      {:ok, value} -> value
      :error -> Map.get(map, string_key)
    end
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
