defmodule JidoDelvetown.ImageGenerator.ReqLLMAdapterTest do
  use ExUnit.Case, async: true

  alias JidoDelvetown.ImageGenerator
  alias JidoDelvetown.ImageGenerator.{Error, ReqLLMAdapter, Request, Result}
  alias ReqLLM.{Context, Message, Response}
  alias ReqLLM.Message.ContentPart

  @bytes <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "generated">>
  @now ~U[2026-10-06 15:00:00Z]

  test "maps an OpenAI request and returns canonical byte-backed data" do
    parent = self()

    client = fn model, prompt, opts ->
      send(parent, {:request, model, prompt, opts})
      {:ok, response()}
    end

    assert {:ok, %Result{} = result} =
             ImageGenerator.generate(ReqLLMAdapter, request(),
               client: client,
               env_reader: env_reader(" sk-test-secret "),
               now: @now
             )

    assert_receive {:request, "openai:gpt-image-1.5", "AgentJido at a workbench", opts}
    assert opts[:api_key] == "sk-test-secret"
    assert opts[:size] == {1024, 1024}
    assert opts[:quality] == "medium"
    assert opts[:output_format] == :png
    assert opts[:response_format] == :binary
    assert opts[:total_timeout] == 120_000
    assert opts[:receive_timeout] == 120_000
    assert opts[:max_retries] == 0
    assert opts[:background] == :opaque
    assert opts[:moderation] == :low
    assert opts[:user] == "high"
    refute Keyword.has_key?(opts, :provider_options)

    assert {:ok, %Req.Request{}} =
             ReqLLM.Providers.OpenAI.prepare_request(
               :image,
               "openai:gpt-image-1.5",
               "AgentJido at a workbench",
               opts
             )

    assert result.image.bytes == @bytes
    assert result.image.media_type == "image/png"
    assert result.image.width == 1024
    assert result.image.height == 1024
    assert result.image.metadata.revised_prompt == "A careful green robot at a workbench"
    assert result.usage.generated_images == 1
    assert result.usage.input_tokens == 20
    assert result.usage.output_tokens == 5
    assert result.usage.total_tokens == 25
    assert result.usage.total_cost == 0.04
    assert result.usage.currency == "USD"
    assert result.provenance.adapter == "req_llm"
    assert result.provenance.response_id == "img_response_123"
    assert result.provenance.generated_at == @now
    assert result.provider_metadata.provider_metadata.openai.body == "[REDACTED]"
    refute inspect(result) =~ "sk-test-secret"
  end

  test "reads the API key only from the external secret source" do
    parent = self()

    client = fn _model, _prompt, _opts ->
      send(parent, :called)
      {:ok, response()}
    end

    assert {:error,
            %Error{
              kind: :authentication,
              outcome: :not_started,
              details: %{environment: "OPENAI_API_KEY"}
            }} =
             ImageGenerator.generate(ReqLLMAdapter, request(),
               client: client,
               env_reader: env_reader(nil)
             )

    refute_receive :called

    assert {:error, %Error{kind: :invalid_request, outcome: :not_started}} =
             Request.new(
               provider: "openai",
               model: "gpt-image-1.5",
               prompt: "robot",
               provider_options: %{openai: %{api_key: "must-not-be-persisted"}}
             )
  end

  test "rejects non-OpenAI providers and reserved request options before a call" do
    parent = self()

    client = fn _model, _prompt, _opts ->
      send(parent, :called)
      {:ok, response()}
    end

    assert {:error, %Error{kind: :unsupported, outcome: :not_started}} =
             ImageGenerator.generate(
               ReqLLMAdapter,
               request(provider: "google"),
               client: client,
               env_reader: env_reader("key")
             )

    assert {:error, %Error{kind: :invalid_request, outcome: :not_started}} =
             ImageGenerator.generate(
               ReqLLMAdapter,
               request(provider_options: %{"max_retries" => 3}),
               client: client,
               env_reader: env_reader("key")
             )

    assert {:error, %Error{kind: :invalid_request, outcome: :not_started}} =
             ImageGenerator.generate(
               ReqLLMAdapter,
               request(provider_options: %{"openai" => %{"auth_mode" => "oauth"}}),
               client: client,
               env_reader: env_reader("key")
             )

    refute_receive :called
  end

  test "rejects URL-only, missing, and multiple image responses" do
    for response <- [
          response(parts: [ContentPart.image_url("https://temporary.example/image.png")]),
          response(parts: []),
          response(parts: [ContentPart.image(@bytes), ContentPart.image(@bytes)])
        ] do
      assert {:error, %Error{kind: :invalid_response, outcome: :failed}} =
               generate_with_response(response)
    end
  end

  test "classifies provider responses without retaining provider bodies" do
    provider_error =
      ReqLLM.Error.API.Request.exception(
        reason: "rate limited with sensitive-provider-text",
        status: 429,
        provider_code: "rate_limit",
        response_body: %{"secret" => "sensitive-provider-text"},
        retryable: true
      )

    assert {:error,
            %Error{
              kind: :rate_limited,
              outcome: :failed,
              retryable?: true,
              provider_status: 429,
              provider_code: "rate_limit"
            } = error} = generate_with_error(provider_error)

    refute inspect(error) =~ "sensitive-provider-text"
  end

  test "classifies transport and timeout errors as uncertain" do
    network_error =
      ReqLLM.Error.API.Request.exception(
        reason: "connection stopped",
        cause: %Req.TransportError{reason: :timeout}
      )

    assert {:error, %Error{kind: :network, outcome: :unknown, retryable?: true}} =
             generate_with_error(network_error)

    timeout_error = ReqLLM.Error.API.Timeout.exception(kind: :total, timeout: 120_000)

    assert {:error, %Error{kind: :timeout, outcome: :unknown}} =
             generate_with_error(timeout_error)
  end

  test "enforces the request total timeout around an injected client" do
    slow_client = fn _model, _prompt, _opts ->
      Process.sleep(5_000)
      {:ok, response()}
    end

    started_at = System.monotonic_time(:millisecond)

    assert {:error,
            %Error{
              kind: :timeout,
              outcome: :unknown,
              details: %{timeout_ms: 1_000}
            }} =
             ImageGenerator.generate(
               ReqLLMAdapter,
               request(timeout_ms: 1_000),
               client: slow_client,
               env_reader: env_reader("key")
             )

    assert System.monotonic_time(:millisecond) - started_at < 2_000
  end

  test "does not expose an injected client exception" do
    client = fn _model, _prompt, _opts -> raise "sensitive exception body" end

    assert {:error, %Error{kind: :internal, outcome: :unknown} = error} =
             ImageGenerator.generate(ReqLLMAdapter, request(),
               client: client,
               env_reader: env_reader("key")
             )

    refute inspect(error) =~ "sensitive exception body"
  end

  defp generate_with_response(response) do
    ImageGenerator.generate(ReqLLMAdapter, request(),
      client: fn _model, _prompt, _opts -> {:ok, response} end,
      env_reader: env_reader("key"),
      now: @now
    )
  end

  defp generate_with_error(error) do
    ImageGenerator.generate(ReqLLMAdapter, request(),
      client: fn _model, _prompt, _opts -> {:error, error} end,
      env_reader: env_reader("key")
    )
  end

  defp request(overrides \\ []) do
    attrs = %{
      prompt: "AgentJido at a workbench",
      provider: "openai",
      model: "gpt-image-1.5",
      size: {1024, 1024},
      quality: "medium",
      output_format: :png,
      timeout_ms: 120_000,
      provider_options: %{
        "background" => "opaque",
        "moderation" => "low",
        "user" => "high"
      }
    }

    {:ok, request} = Request.new(Map.merge(attrs, Map.new(overrides)))
    request
  end

  defp response(opts \\ []) do
    parts =
      Keyword.get(opts, :parts, [
        ContentPart.image(@bytes, "image/png", %{
          revised_prompt: "A careful green robot at a workbench"
        })
      ])

    %Response{
      id: "img_response_123",
      model: "gpt-image-1.5",
      context: Context.new(),
      message: %Message{role: :assistant, content: parts},
      usage: %{
        input_tokens: 20,
        output_tokens: 5,
        total_tokens: 25,
        total_cost: 0.04,
        pricing: %{status: :priced, currency: "USD", total: 0.04},
        image_usage: %{generated: %{count: 1}}
      },
      finish_reason: :stop,
      provider_meta: %{
        openai: %{
          request_id: "req_123",
          body: "provider response bytes must not survive"
        }
      }
    }
  end

  defp env_reader(value), do: fn "OPENAI_API_KEY" -> value end
end
