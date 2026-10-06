defmodule JidoDelvetown.ParticipationImageGenerationTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{
    ImageDrafts,
    ImageGenerationRequests,
    ParticipationImageGeneration,
    Repo,
    Settings
  }

  alias JidoDelvetown.ImageGenerator.{Image, Provenance, Result, Usage}
  alias JidoDelvetown.Settings.Bootstrap
  alias JidoDelvetown.Storage.{ImageArtifact, ImageDraft, ImageGenerationRequest}

  defmodule SuccessfulGenerator do
    @behaviour JidoDelvetown.ImageGenerator

    @impl true
    def generate(request, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:generate_image, request})

      {:ok, image} =
        Image.new(
          bytes: <<0x89, 0x50, 0x4E, 0x47, "participation-generated-image">>,
          media_type: "image/png",
          width: 1024,
          height: 1024
        )

      {:ok, usage} = Usage.new(generated_images: 1, total_cost: 0.03, currency: "USD")

      {:ok, provenance} =
        Provenance.new(request,
          adapter: "test_generator",
          response_id: "participation_response_1",
          generated_at: ~U[2026-10-06 16:00:00Z]
        )

      Result.new(
        image: image,
        usage: usage,
        provenance: provenance,
        elapsed_ms: 750,
        provider_metadata: %{request_id: "safe_participation_request_id"}
      )
    end
  end

  setup do
    clear_generation_records()
    on_exit(&clear_generation_records/0)

    scope = "participation-generation-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)
    %{scope: scope, now: ~U[2026-10-06 16:00:00Z]}
  end

  test "reports policy denial without a provider call or a durable request", context do
    denied = ParticipationImageGeneration.proposal_context("proactive", policy_opts(context))
    refute denied.allowed?
    assert denied.reason == "image_generation_disabled"
    refute denied.will_generate_and_stage?
    refute denied.will_upload?
    refute denied.will_publish?

    enable_generation(context.scope, ["manual"])

    mode_denied =
      ParticipationImageGeneration.proposal_context("proactive", policy_opts(context))

    refute mode_denied.allowed?
    assert mode_denied.reason == "image_generation_mode_not_allowed"

    assert {:error, {:image_generation_mode_not_allowed, "proactive"}} =
             ParticipationImageGeneration.generate(
               cycle(),
               decision(),
               execution_opts(context)
             )

    refute_receive {:generate_image, _request}
    assert Repo.aggregate(ImageGenerationRequest, :count, :request_key) == 0
    assert Repo.aggregate(ImageDraft, :count, :draft_key) == 0
  end

  test "consumes the generation budget, stages once, and never publishes", context do
    enable_generation(context.scope, ["proactive"])

    allowed = ParticipationImageGeneration.proposal_context("proactive", policy_opts(context))
    assert allowed.allowed?
    assert allowed.operation == "generate_and_stage_image"
    assert allowed.daily_budget.used == 0
    assert allowed.daily_budget.remaining == 1
    assert allowed.will_generate_and_stage?
    refute allowed.will_upload?
    refute allowed.will_publish?

    assert {:ok, saved} =
             ParticipationImageGeneration.generate(
               cycle(),
               decision(),
               execution_opts(context)
             )

    assert_receive {:generate_image, request}
    assert request.prompt == decision().image_prompt
    assert request.metadata["source"] == "proactive_participation"
    assert request.metadata["mode"] == "proactive"

    expected_key =
      ParticipationImageGeneration.request_key("proactive", cycle().candidate.id)

    assert saved.draft_id == expected_key
    assert saved.generation_request_id == expected_key
    assert saved.draft_state == "staged"
    assert saved.generation_state == :completed
    refute saved.uploaded_by_command?
    refute saved.published_by_command?

    draft = ImageDrafts.get(expected_key)
    assert draft.caption == decision().text
    assert draft.alt_text == decision().image_alt_text
    assert draft.post_effect_key == nil
    assert draft.post_receipt == nil
    assert ImageGenerationRequests.daily_usage(now: context.now).used == 1

    budget_denied =
      ParticipationImageGeneration.proposal_context("proactive", policy_opts(context))

    refute budget_denied.allowed?
    assert budget_denied.reason == "image_generation_daily_limit_reached"

    assert {:ok, reused} =
             ParticipationImageGeneration.generate(
               cycle(),
               decision(),
               execution_opts(context)
             )

    refute_receive {:generate_image, _request}
    assert reused.reused?
    refute reused.provider_call_performed?
    assert ImageGenerationRequests.get(expected_key).attempt_count == 1

    changed = %{decision() | image_prompt: "A changed image prompt"}

    assert {:error, {:generation_request_conflict, :request_fingerprint}} =
             ParticipationImageGeneration.generate(cycle(), changed, execution_opts(context))

    refute_receive {:generate_image, _request}
  end

  defp cycle do
    %{kind: "proactive", candidate: %{id: "daily:2026-10-06"}}
  end

  defp decision do
    %{
      action: "post",
      text: "A visual note about clear process boundaries.",
      image_prompt: "A precise diagram of three supervised BEAM processes",
      image_alt_text: "Three supervised BEAM processes form clear failure boundaries."
    }
  end

  defp enable_generation(scope, modes) do
    assert {:ok, _settings} =
             Settings.update(
               %{
                 image_generation_enabled: true,
                 image_generation_allowed_modes: modes,
                 daily_image_generation_limit: 1
               },
               scope: scope,
               confirmed: [:image_generation_enabled]
             )
  end

  defp policy_opts(context), do: [scope: context.scope, now: context.now]

  defp execution_opts(context) do
    policy_opts(context) ++
      [generator: SuccessfulGenerator, generator_options: [test_pid: self()]]
  end

  defp clear_generation_records do
    Repo.delete_all(ImageGenerationRequest)
    Repo.delete_all(ImageDraft)
    Repo.delete_all(ImageArtifact)
  end
end
