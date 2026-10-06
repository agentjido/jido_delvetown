defmodule JidoDelvetown.ManualImageGenerationTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{
    ImageDrafts,
    ImageGenerationRequests,
    ManualImageGeneration,
    Repo,
    Settings
  }

  alias JidoDelvetown.ImageGenerator.{Error, Image, Provenance, Result, Usage}
  alias JidoDelvetown.Settings.Bootstrap
  alias JidoDelvetown.Storage.{ImageArtifact, ImageDraft, ImageGenerationRequest}

  defmodule SuccessfulGenerator do
    @behaviour JidoDelvetown.ImageGenerator

    @impl true
    def generate(request, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:generate_image, request})

      {:ok, image} =
        Image.new(
          bytes: <<0x89, 0x50, 0x4E, 0x47, "manual-generated-image">>,
          media_type: "image/png",
          width: 1024,
          height: 1024
        )

      {:ok, usage} =
        Usage.new(generated_images: 1, total_cost: 0.02, currency: "USD")

      {:ok, provenance} =
        Provenance.new(request,
          adapter: "test_generator",
          response_id: "manual_response_1",
          generated_at: ~U[2026-10-06 15:00:00Z]
        )

      Result.new(
        image: image,
        usage: usage,
        provenance: provenance,
        elapsed_ms: 900,
        provider_metadata: %{request_id: "safe_request_id"}
      )
    end
  end

  defmodule MissingCredentialGenerator do
    @behaviour JidoDelvetown.ImageGenerator

    @impl true
    def generate(_request, opts) do
      send(Keyword.fetch!(opts, :test_pid), :generation_attempted)

      {:error,
       Error.new(:authentication, "OpenAI API key is not configured", outcome: :not_started)}
    end
  end

  setup do
    clear_generation_records()
    on_exit(&clear_generation_records/0)

    scope = "manual-generation-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)
    %{scope: scope, now: ~U[2026-10-06 15:00:00Z]}
  end

  test "keeps disabled settings safe and rejects invalid draft copy", context do
    assert {:error, :image_generation_disabled} =
             ManualImageGeneration.plan(input(), policy_opts(context))

    enable_generation(context.scope)

    assert {:error, {:missing_manual_image_generation_field, :alt_text}} =
             ManualImageGeneration.plan(
               %{input() | alt_text: ""},
               policy_opts(context)
             )

    assert Repo.aggregate(ImageGenerationRequest, :count, :request_key) == 0
    assert Repo.aggregate(ImageDraft, :count, :draft_key) == 0
  end

  test "builds a read-only preview with the exact operation settings", context do
    enable_generation(context.scope)

    assert {:ok, plan} = ManualImageGeneration.plan(input(), policy_opts(context))
    estimate = ManualImageGeneration.estimate(plan)

    assert estimate.operation == "generate_and_stage_image"
    assert estimate.generation_request_id == input().key
    assert estimate.draft_id == input().key
    assert estimate.provider == "openai"
    assert estimate.model == "gpt-image-1-mini"
    assert estimate.size == "1024x1024"
    assert estimate.quality == "medium"
    assert estimate.output_format == :png
    assert estimate.timeout_ms == 120_000
    assert estimate.daily_budget.used == 0
    assert estimate.daily_budget.remaining == 1
    assert estimate.estimated_provider_calls == 1
    refute estimate.reuses_completed_request?
    refute estimate.will_upload?
    refute estimate.will_publish?
    assert estimate.prompt.bytes == byte_size(input().prompt)
    refute Map.has_key?(estimate.prompt, :text)

    assert Repo.aggregate(ImageGenerationRequest, :count, :request_key) == 0
    assert Repo.aggregate(ImageDraft, :count, :draft_key) == 0
    assert Repo.aggregate(ImageArtifact, :count, :digest) == 0
  end

  test "generates once, stages the draft, and reuses the durable result", context do
    enable_generation(context.scope)
    opts = execution_opts(context, SuccessfulGenerator)

    assert {:ok, plan} = ManualImageGeneration.plan(input(), policy_opts(context))
    assert {:ok, saved} = ManualImageGeneration.execute(plan, opts)

    assert_receive {:generate_image, request}
    assert request.prompt == input().prompt
    assert request.model == "gpt-image-1-mini"
    assert request.size == {1024, 1024}

    assert saved.draft_id == input().key
    assert saved.generation_request_id == input().key
    assert saved.draft_state == "staged"
    assert saved.generation_state == :completed
    assert saved.provider_call_performed?
    refute saved.reused?
    refute saved.uploaded_by_command?
    refute saved.published_by_command?
    assert saved.provenance["provider"] == "openai"
    assert saved.provenance["response_id"] == "manual_response_1"
    assert saved.usage["total_cost"] == 0.02

    stored = ImageGenerationRequests.get(input().key)
    assert stored.state == :completed
    assert stored.artifact_digest == saved.artifact_digest
    assert stored.attempt_count == 1

    draft = ImageDrafts.get(input().key)
    assert draft.caption == input().caption
    assert draft.alt_text == input().alt_text
    assert draft.artifact.state == "staged"
    assert draft.post_effect_key == nil
    assert draft.post_receipt == nil

    assert {:ok, reuse_plan} = ManualImageGeneration.plan(input(), policy_opts(context))
    assert reuse_plan.estimated_provider_calls == 0
    assert reuse_plan.reuses_completed_request?

    assert {:ok, reused} = ManualImageGeneration.execute(reuse_plan, opts)
    refute_receive {:generate_image, _request}
    refute reused.provider_call_performed?
    assert reused.reused?
    assert reused.artifact_digest == saved.artifact_digest
    assert ImageGenerationRequests.get(input().key).attempt_count == 1
  end

  test "stops when settings change after the preview", context do
    enable_generation(context.scope)
    assert {:ok, plan} = ManualImageGeneration.plan(input(), policy_opts(context))

    assert {:ok, _updated} =
             Settings.update(
               %{image_generation_quality: "high"},
               scope: context.scope
             )

    assert {:error, :image_generation_settings_changed} =
             ManualImageGeneration.execute(
               plan,
               execution_opts(context, SuccessfulGenerator)
             )

    refute_receive {:generate_image, _request}
    assert ImageGenerationRequests.get(input().key) == nil
  end

  test "records a pre-call failure and leaves the request safe to retry", context do
    enable_generation(context.scope)
    assert {:ok, plan} = ManualImageGeneration.plan(input(), policy_opts(context))

    assert {:error, {:image_generation_failed, %Error{outcome: :not_started}}} =
             ManualImageGeneration.execute(
               plan,
               execution_opts(context, MissingCredentialGenerator)
             )

    assert_receive :generation_attempted
    stored = ImageGenerationRequests.get(input().key)
    assert stored.state == :reserved
    assert stored.attempt_count == 1
    assert stored.failure["kind"] == "authentication"
    assert ImageGenerationRequests.daily_usage(now: context.now).used == 0
    assert ImageDrafts.get(input().key) == nil
  end

  defp input do
    %{
      key: "manual:workbench:v1",
      prompt: "AgentJido at a careful workbench",
      caption: "A new idea takes shape.",
      alt_text: "A green robot works at a desk."
    }
  end

  defp enable_generation(scope) do
    assert {:ok, _settings} =
             Settings.update(
               %{
                 image_generation_enabled: true,
                 image_generation_allowed_modes: ["manual"],
                 daily_image_generation_limit: 1
               },
               scope: scope,
               confirmed: [:image_generation_enabled]
             )
  end

  defp policy_opts(context), do: [scope: context.scope, now: context.now]

  defp execution_opts(context, generator) do
    policy_opts(context) ++ [generator: generator, generator_options: [test_pid: self()]]
  end

  defp clear_generation_records do
    Repo.delete_all(ImageGenerationRequest)
    Repo.delete_all(ImageDraft)
    Repo.delete_all(ImageArtifact)
  end
end
