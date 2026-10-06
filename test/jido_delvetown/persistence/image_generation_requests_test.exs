defmodule JidoDelvetown.ImageGenerationRequestsTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{ImageDrafts, ImageGenerationRequests, Repo}
  alias JidoDelvetown.ImageGenerator.{Error, Image, Provenance, Request, Result, Usage}
  alias JidoDelvetown.Storage.{ImageArtifact, ImageDraft, ImageGenerationRequest}

  @bytes <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "generated-image">>

  setup do
    clear_records()
    on_exit(&clear_records/0)
    :ok
  end

  test "reserves one stable request and restores its normalized inputs" do
    request = request(metadata: %{trace: "first"}, provider_options: %{background: :opaque})

    assert {:ok, %{request: first, reused?: false}} =
             ImageGenerationRequests.reserve("portrait:v1", request)

    assert first.state == :reserved
    assert first.attempt_count == 0
    assert first.options["provider_options"] == %{"background" => "opaque"}

    assert {:ok, %{request: second, reused?: true}} =
             ImageGenerationRequests.reserve("portrait:v1", request)

    assert second.request_fingerprint == first.request_fingerprint
    assert Repo.aggregate(ImageGenerationRequest, :count, :request_key) == 1

    assert {:ok, restored} = ImageGenerationRequests.load_request("portrait:v1")
    assert restored.provider_options == %{"background" => "opaque"}
    assert restored.metadata == %{"trace" => "first"}
    assert Request.fingerprint(restored) == first.request_fingerprint
  end

  test "rejects a different request for an existing key" do
    assert {:ok, _reservation} =
             ImageGenerationRequests.reserve("stable", request(prompt: "First prompt"))

    assert {:error, {:generation_request_conflict, :request_fingerprint}} =
             ImageGenerationRequests.reserve("stable", request(prompt: "Changed prompt"))
  end

  test "concurrent reservations create one row" do
    reservations =
      1..12
      |> Task.async_stream(
        fn _index -> ImageGenerationRequests.reserve("concurrent", request()) end,
        max_concurrency: 12,
        ordered: false
      )
      |> Enum.map(fn {:ok, {:ok, reservation}} -> reservation end)

    assert length(reservations) == 12
    assert Repo.aggregate(ImageGenerationRequest, :count, :request_key) == 1
    assert Enum.count(reservations, &(&1.reused? == false)) == 1
  end

  test "marks the outcome uncertain before a provider call and blocks another attempt" do
    assert {:ok, _reservation} = ImageGenerationRequests.reserve("uncertain", request())

    assert {:ok, %{request: started, reused?: false}} =
             ImageGenerationRequests.begin_attempt("uncertain")

    assert started.state == :uncertain
    assert started.attempt_count == 1
    assert started.attempted_at

    assert {:error, :generation_outcome_uncertain} =
             ImageGenerationRequests.begin_attempt("uncertain")

    assert {:ok, %{request: failed}} =
             ImageGenerationRequests.record_failure(
               "uncertain",
               Error.timeout(%{timeout_ms: 120_000})
             )

    assert failed.state == :uncertain
    assert failed.failure["outcome"] == "unknown"

    assert {:error, :generation_outcome_uncertain} =
             ImageGenerationRequests.begin_attempt("uncertain")
  end

  test "a pre-call failure can return to reserved while a definite provider failure is terminal" do
    assert {:ok, _reservation} = ImageGenerationRequests.reserve("safe-retry", request())
    assert {:ok, _started} = ImageGenerationRequests.begin_attempt("safe-retry")

    not_started =
      Error.new(:authentication, "missing key",
        outcome: :not_started,
        details: %{source: :external_secret}
      )

    assert {:ok, %{request: retryable}} =
             ImageGenerationRequests.record_failure("safe-retry", not_started)

    assert retryable.state == :reserved
    assert retryable.failure["kind"] == "authentication"

    assert {:ok, %{request: second_attempt}} =
             ImageGenerationRequests.begin_attempt("safe-retry")

    assert second_attempt.attempt_count == 2

    failed = Error.new(:provider, "content rejected", outcome: :failed, provider_status: 400)

    assert {:ok, %{request: terminal}} =
             ImageGenerationRequests.record_failure("safe-retry", failed)

    assert terminal.state == :failed
    assert terminal.completed_at

    assert {:error, {:invalid_generation_state, "failed"}} =
             ImageGenerationRequests.begin_attempt("safe-retry")
  end

  test "stores a completed receipt linked to the exact staged artifact" do
    request = request()
    assert {:ok, _reservation} = ImageGenerationRequests.reserve("complete", request)
    assert {:ok, _started} = ImageGenerationRequests.begin_attempt("complete")
    assert {:ok, staged} = stage_artifact("complete")
    result = result(request)

    assert {:ok, %{request: completed, reused?: false}} =
             ImageGenerationRequests.complete(
               "complete",
               staged.artifact.digest,
               result
             )

    assert completed.state == :completed
    assert completed.artifact_digest == staged.artifact.digest
    assert completed.usage["generated_images"] == 1
    assert completed.usage["total_cost"] == 0.04
    assert completed.response_metadata["provenance"]["response_id"] == "resp_123"
    assert completed.response_metadata["image"]["byte_size"] == byte_size(@bytes)
    refute Map.has_key?(completed.response_metadata["image"], "bytes")

    assert {:ok, %{request: reused, reused?: true}} =
             ImageGenerationRequests.complete("complete", staged.artifact.digest, result)

    assert reused.completed_at == completed.completed_at

    assert {:ok, %{request: reserved_again, reused?: true}} =
             ImageGenerationRequests.reserve("complete", request)

    assert reserved_again.state == :completed

    assert {:ok, %{request: no_second_call, reused?: true}} =
             ImageGenerationRequests.begin_attempt("complete")

    assert no_second_call.attempt_count == 1
  end

  test "rejects a receipt from another request or artifact" do
    request = request()
    assert {:ok, _reservation} = ImageGenerationRequests.reserve("mismatch", request)
    assert {:ok, _started} = ImageGenerationRequests.begin_attempt("mismatch")
    assert {:ok, staged} = stage_artifact("mismatch")

    assert {:error, :generation_request_fingerprint_mismatch} =
             ImageGenerationRequests.complete(
               "mismatch",
               staged.artifact.digest,
               result(request(prompt: "Another prompt"))
             )

    assert {:error, :generation_artifact_not_found} =
             ImageGenerationRequests.complete("mismatch", "sha256:missing", result(request))

    assert ImageGenerationRequests.get("mismatch").state == :uncertain
  end

  test "reports all generation state counts" do
    assert {:ok, _reservation} = ImageGenerationRequests.reserve("reserved", request())
    assert {:ok, _reservation} = ImageGenerationRequests.reserve("uncertain", request())
    assert {:ok, _started} = ImageGenerationRequests.begin_attempt("uncertain")

    assert ImageGenerationRequests.counts() == %{
             reserved: 1,
             uncertain: 1,
             failed: 0,
             completed: 0
           }
  end

  defp request(overrides \\ []) do
    attrs = %{
      prompt: "AgentJido at a careful workbench",
      provider: "openai",
      model: "gpt-image-1.5",
      size: {1024, 1024},
      quality: "medium",
      output_format: :png,
      timeout_ms: 120_000,
      provider_options: %{},
      metadata: %{}
    }

    {:ok, request} = Request.new(Map.merge(attrs, Map.new(overrides)))
    request
  end

  defp result(request) do
    {:ok, image} =
      Image.new(
        bytes: @bytes,
        media_type: "image/png",
        width: 1024,
        height: 1024,
        metadata: %{revised_prompt: "A careful green robot"}
      )

    {:ok, usage} =
      Usage.new(
        generated_images: 1,
        input_tokens: 20,
        output_tokens: 5,
        total_tokens: 25,
        total_cost: 0.04,
        currency: "USD",
        raw: %{image_usage: %{generated: %{count: 1}}}
      )

    {:ok, provenance} =
      Provenance.new(request,
        adapter: "req_llm",
        response_id: "resp_123",
        revised_prompt: "A careful green robot",
        generated_at: ~U[2026-10-06 12:00:00Z]
      )

    {:ok, result} =
      Result.new(
        image: image,
        usage: usage,
        provenance: provenance,
        elapsed_ms: 3_200,
        provider_metadata: %{request_id: "req_123"}
      )

    result
  end

  defp stage_artifact(key) do
    ImageDrafts.stage("generation:#{key}", @bytes, %{
      caption: "AgentJido at a careful workbench.",
      alt_text: "A green robot works at a desk.",
      mime_type: "image/png",
      width: 1024,
      height: 1024,
      source_metadata: %{source: "generation_test"}
    })
  end

  defp clear_records do
    Repo.delete_all(ImageGenerationRequest)
    Repo.delete_all(ImageDraft)
    Repo.delete_all(ImageArtifact)
  end
end
