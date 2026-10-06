defmodule JidoDelvetown.ImageGenerationStager do
  @moduledoc """
  Stages a generated image and completes its durable generation receipt.

  The result is checked against the reserved generation request before bytes
  are staged. `ImageStager` then applies the current DelveTown image limits.
  Staging and receipt completion use one SQLite transaction. A retry with the
  same request, draft key, result, caption, and alt text reuses both durable
  records.
  """

  alias JidoDelvetown.{ImageGenerationRequests, ImageStager, Repo}
  alias JidoDelvetown.ImageGenerator.Result

  @type stage_result :: %{
          draft: map(),
          artifact: map(),
          generation_request: map(),
          reused?: boolean(),
          draft_reused?: boolean(),
          artifact_reused?: boolean(),
          generation_request_reused?: boolean()
        }

  @doc """
  Stages one generated result under a stable draft key.

  `attrs` must contain a caption and alt text. Image bytes, MIME type,
  dimensions, and generation metadata always come from the validated result.
  This function does not upload or publish the image.
  """
  @spec stage(String.t(), String.t(), Result.t(), map()) ::
          {:ok, stage_result()} | {:error, term()}
  def stage(request_key, draft_key, %Result{} = result, attrs)
      when is_binary(request_key) and is_binary(draft_key) and is_map(attrs) do
    with :ok <- Result.validate(result) do
      Repo.transaction(
        fn -> stage_transaction(request_key, draft_key, result, attrs) end,
        mode: :immediate
      )
      |> transaction_result()
    end
  end

  def stage(_request_key, _draft_key, _result, _attrs),
    do: {:error, :invalid_generation_stage_request}

  defp stage_transaction(request_key, draft_key, result, attrs) do
    with {:ok, stored_request} <- generation_request(request_key),
         :ok <- validate_result(stored_request, result),
         {:ok, staged} <- stage_result(request_key, draft_key, result, attrs),
         {:ok, completion} <-
           ImageGenerationRequests.complete(
             request_key,
             staged.artifact.digest,
             result
           ) do
      combine(staged, completion)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp generation_request(request_key) do
    case ImageGenerationRequests.get(request_key) do
      nil -> {:error, :generation_request_not_found}
      request -> {:ok, request}
    end
  end

  defp validate_result(request, result) do
    provenance = result.provenance
    digest = "sha256:" <> result.image.digest

    cond do
      request.state not in [:uncertain, :completed] ->
        {:error, {:invalid_generation_state, Atom.to_string(request.state)}}

      provenance.request_fingerprint != request.request_fingerprint ->
        {:error, :generation_request_fingerprint_mismatch}

      provenance.provider != request.provider or provenance.model != request.model ->
        {:error, :generation_provider_mismatch}

      request.state == :completed and request.artifact_digest != digest ->
        {:error, :generation_receipt_conflict}

      true ->
        :ok
    end
  end

  defp stage_result(request_key, draft_key, result, attrs) do
    ImageStager.stage_bytes(draft_key, result.image.bytes, %{
      caption: value(attrs, :caption),
      alt_text: value(attrs, :alt_text),
      mime_type: result.image.media_type,
      width: result.image.width,
      height: result.image.height,
      source_metadata: source_metadata(request_key, result)
    })
  end

  defp source_metadata(request_key, result) do
    provenance = result.provenance

    %{
      source: "image_generation",
      generation_request_id: request_key,
      provider: provenance.provider,
      model: provenance.model,
      adapter: provenance.adapter,
      provider_response_id: provenance.response_id,
      generated_at: provenance.generated_at,
      elapsed_ms: result.elapsed_ms,
      prompt_provenance: %{
        prompt_sha256: provenance.prompt_sha256,
        request_fingerprint: provenance.request_fingerprint,
        revised_prompt: provenance.revised_prompt
      },
      usage: Map.from_struct(result.usage)
    }
  end

  defp combine(staged, completion) do
    %{
      draft: staged.draft,
      artifact: staged.artifact,
      generation_request: completion.request,
      reused?: staged.reused? and completion.reused?,
      draft_reused?: staged.reused?,
      artifact_reused?: staged.artifact_reused?,
      generation_request_reused?: completion.reused?
    }
  end

  defp transaction_result({:ok, value}), do: {:ok, value}
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
