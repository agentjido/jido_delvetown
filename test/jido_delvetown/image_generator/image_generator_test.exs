defmodule JidoDelvetown.ImageGeneratorTest do
  use ExUnit.Case, async: true

  alias JidoDelvetown.ImageGenerator
  alias JidoDelvetown.ImageGenerator.{Error, Image, Provenance, Request, Result, Usage}

  defmodule ValidAdapter do
    @behaviour ImageGenerator

    @impl true
    def generate(request, opts) do
      {:ok, image} =
        Image.new(bytes: "png-bytes", media_type: "image/png", width: 1024, height: 1024)

      {:ok, usage} =
        Usage.new(generated_images: 1, input_tokens: 12, total_cost: 0.04, currency: "usd")

      {:ok, provenance} =
        Provenance.new(request,
          adapter: __MODULE__,
          response_id: "image-response-1",
          revised_prompt: "A precise green robot",
          generated_at: ~U[2026-10-06 12:00:00Z]
        )

      Result.new(
        image: image,
        usage: usage,
        provenance: provenance,
        elapsed_ms: Keyword.fetch!(opts, :elapsed_ms),
        provider_metadata: %{request_id: "req_123"}
      )
    end
  end

  defmodule InvalidAdapter do
    @behaviour ImageGenerator

    @impl true
    def generate(_request, _opts), do: {:ok, %{url: "https://temporary.example/image.png"}}
  end

  defmodule InvalidErrorAdapter do
    @behaviour ImageGenerator

    @impl true
    def generate(_request, _opts), do: {:error, %Error{kind: :not_a_contract_kind}}
  end

  test "normalizes inputs supported by the first OpenAI ReqLLM target" do
    assert {:ok, request} =
             Request.new(%{
               "prompt" => "  AgentJido at a careful workbench  ",
               "provider" => "openai",
               "model" => "gpt-image-1.5",
               "size" => "1024x1024",
               "quality" => :medium,
               "output_format" => "PNG",
               "timeout_ms" => 180_000,
               "provider_options" => %{"background" => "opaque"},
               "metadata" => %{"request_key" => "portrait:v1"}
             })

    assert request.prompt == "AgentJido at a careful workbench"
    assert request.provider == "openai"
    assert request.model == "gpt-image-1.5"
    assert request.size == {1024, 1024}
    assert request.quality == "medium"
    assert request.output_format == :png
    assert request.timeout_ms == 180_000
    assert request.provider_options == %{"background" => "opaque"}
  end

  test "rejects invalid request inputs before an adapter call" do
    assert {:error, %Error{kind: :invalid_request, outcome: :not_started}} =
             Request.new(provider: "openai", model: "gpt-image-1.5", prompt: " ")

    assert {:error, %Error{details: %{field: :size}}} =
             Request.new(
               provider: "openai",
               model: "gpt-image-1.5",
               prompt: "robot",
               size: "wide"
             )

    assert {:error, %Error{details: %{field: :timeout_ms}}} =
             Request.new(
               provider: "openai",
               model: "gpt-image-1.5",
               prompt: "robot",
               timeout_ms: 20
             )
  end

  test "request fingerprints are stable and exclude local metadata" do
    attrs = %{
      provider: "openai",
      model: "gpt-image-1.5",
      prompt: "AgentJido portrait",
      size: {1024, 1024},
      provider_options: %{background: "opaque", moderation: "auto"}
    }

    assert {:ok, first} = Request.new(Map.put(attrs, :metadata, %{trace: "one"}))

    assert {:ok, second} =
             Request.new(%{
               attrs
               | provider_options: %{moderation: "auto", background: "opaque"}
             })

    assert Request.fingerprint(first) == Request.fingerprint(second)

    assert {:ok, changed} = Request.new(%{attrs | prompt: "Different portrait"})
    refute Request.fingerprint(first) == Request.fingerprint(changed)
  end

  test "generated image records byte integrity and paired dimensions" do
    assert {:ok, image} =
             Image.new(bytes: <<1, 2, 3>>, media_type: "IMAGE/PNG", width: 512, height: 768)

    assert image.byte_size == 3
    assert image.media_type == "image/png"
    assert image.digest == Image.digest(<<1, 2, 3>>)
    assert :ok = Image.validate(image)

    assert {:error, %Error{kind: :invalid_response}} =
             Image.new(bytes: <<1>>, media_type: "image/png", width: 512)
  end

  test "usage keeps normalized counters and safe raw data" do
    assert {:ok, usage} =
             Usage.new(%{
               "generated_images" => 1,
               "input_tokens" => 42,
               "output_tokens" => 8,
               "total_tokens" => 50,
               "total_cost" => 0.08,
               "currency" => "usd",
               "raw" => %{"image_usage" => %{"generated" => %{"count" => 1}}}
             })

    assert usage.currency == "USD"
    assert usage.total_tokens == 50
    assert :ok = Usage.validate(usage)
  end

  test "provenance links response data to the exact request without storing the prompt" do
    assert {:ok, request} =
             Request.new(provider: :openai, model: "gpt-image-1.5", prompt: "green robot")

    assert {:ok, provenance} =
             Provenance.new(request,
               adapter: ValidAdapter,
               response_id: "resp_123",
               generated_at: ~U[2026-10-06 12:00:00Z]
             )

    assert provenance.provider == "openai"
    assert provenance.model == "gpt-image-1.5"
    assert provenance.adapter == to_string(ValidAdapter)
    assert provenance.request_fingerprint == Request.fingerprint(request)
    assert byte_size(provenance.prompt_sha256) == 64
    refute Map.has_key?(Map.from_struct(provenance), :prompt)
    assert :ok = Provenance.validate(provenance)
  end

  test "runs a conforming adapter and rejects URL-only or malformed results" do
    request = %{provider: "openai", model: "gpt-image-1.5", prompt: "green robot"}

    assert {:ok, %Result{} = result} =
             ImageGenerator.generate(ValidAdapter, request, elapsed_ms: 3_200)

    assert result.image.bytes == "png-bytes"
    assert result.elapsed_ms == 3_200
    assert result.provenance.response_id == "image-response-1"

    assert {:error, %Error{kind: :adapter_contract, outcome: :unknown}} =
             ImageGenerator.generate(InvalidAdapter, request)

    assert {:error, %Error{kind: :adapter_contract, outcome: :unknown}} =
             ImageGenerator.generate(InvalidErrorAdapter, request)
  end

  test "timeout failures are uncertain and not automatically retryable" do
    error = Error.timeout(%{timeout_ms: 120_000})

    assert error.kind == :timeout
    assert error.outcome == :unknown
    refute error.retryable?
    assert Error.uncertain?(error)
  end
end
