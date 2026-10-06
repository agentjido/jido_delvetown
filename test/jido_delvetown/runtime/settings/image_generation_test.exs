defmodule JidoDelvetown.Settings.ImageGenerationTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{ImageGenerationRequests, Repo, Settings}
  alias JidoDelvetown.ImageGenerator.Request
  alias JidoDelvetown.Settings.{Bootstrap, ImageGeneration}
  alias JidoDelvetown.Storage.ImageGenerationRequest

  setup do
    Repo.delete_all(ImageGenerationRequest)
    on_exit(fn -> Repo.delete_all(ImageGenerationRequest) end)
    :ok
  end

  test "reads safe defaults as normalized request policy" do
    scope = bootstrap_scope()
    now = ~U[2026-10-06 12:00:00Z]

    assert {:ok, policy} = ImageGeneration.current(scope: scope, now: now)
    refute policy.enabled?
    assert policy.provider == "openai"
    assert policy.model == "gpt-image-1-mini"
    assert policy.size == {1024, 1024}
    assert policy.quality == "medium"
    assert policy.output_format == :png
    assert policy.timeout_ms == 120_000
    assert policy.daily_limit == 1
    assert policy.allowed_modes == ["manual"]
    assert policy.budget.used == 0
    assert policy.budget.remaining == 1
    assert policy.settings.schema_version == 3

    assert {:error, :image_generation_disabled} =
             ImageGeneration.authorize("manual", scope: scope, now: now)
  end

  test "requires confirmation and keeps generation separate from publication" do
    scope = bootstrap_scope()

    assert {:error, {:confirmation_required, :image_generation_enabled, true}} =
             Settings.update(%{image_generation_enabled: true}, scope: scope)

    assert {:ok, updated} =
             Settings.update(
               %{
                 image_generation_enabled: true,
                 image_generation_model: "gpt-image-1.5",
                 image_generation_size: "auto",
                 image_generation_quality: "high",
                 image_generation_output_format: "webp",
                 image_generation_timeout_ms: 180_000,
                 daily_image_generation_limit: 2,
                 image_generation_allowed_modes: ["manual", "proactive"]
               },
               scope: scope,
               confirmed: [:image_generation_enabled]
             )

    assert updated.values.image_generation_enabled
    refute updated.values.manual_publish_enabled

    assert {:ok, policy} = ImageGeneration.authorize("proactive", scope: scope)
    assert policy.model == "gpt-image-1.5"
    assert policy.size == :auto
    assert policy.quality == "high"
    assert policy.output_format == :webp
    assert policy.timeout_ms == 180_000
    assert policy.daily_limit == 2

    assert {:error, {:image_generation_mode_not_allowed, "reactive"}} =
             ImageGeneration.authorize("reactive", scope: scope)

    assert {:error, {:invalid_image_generation_mode, "scheduled"}} =
             ImageGeneration.authorize("scheduled", scope: scope)
  end

  test "reports and applies the durable daily budget" do
    scope = bootstrap_scope()
    now = ~U[2026-10-06 12:00:00Z]

    assert {:ok, _updated} =
             Settings.update(
               %{image_generation_enabled: true, daily_image_generation_limit: 1},
               scope: scope,
               confirmed: [:image_generation_enabled]
             )

    request = request()
    assert {:ok, _reservation} = ImageGenerationRequests.reserve("budget:v1", request)

    assert {:ok, policy} = ImageGeneration.authorize("manual", scope: scope, now: now)

    assert {:ok, _started} =
             ImageGenerationRequests.begin_attempt("budget:v1",
               daily_limit: policy.daily_limit,
               now: now
             )

    assert {:error, :image_generation_daily_limit_reached} =
             ImageGeneration.authorize("manual", scope: scope, now: now)
  end

  defp request do
    {:ok, request} =
      Request.new(
        prompt: "AgentJido at a workbench",
        provider: "openai",
        model: "gpt-image-1-mini"
      )

    request
  end

  defp bootstrap_scope do
    scope = "image-generation-settings-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, %{created?: true}} = Bootstrap.run(scope: scope)
    scope
  end
end
