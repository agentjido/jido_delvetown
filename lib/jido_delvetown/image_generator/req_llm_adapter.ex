defmodule JidoDelvetown.ImageGenerator.ReqLLMAdapter do
  @moduledoc """
  Generates one OpenAI image through `ReqLLM.generate_image/3`.

  The adapter reads `OPENAI_API_KEY` from the external environment for each
  call. It returns canonical image bytes and metadata only. It does not persist,
  stage, upload, or publish the result.
  """

  @behaviour JidoDelvetown.ImageGenerator

  alias JidoDelvetown.ImageGenerator.{Error, Image, Provenance, Request, Result, Usage}

  @api_key_environment "OPENAI_API_KEY"
  @adapter_name "req_llm"
  @canonical_option_keys %{
    "aspect_ratio" => :aspect_ratio,
    "background" => :background,
    "input_fidelity" => :input_fidelity,
    "moderation" => :moderation,
    "negative_prompt" => :negative_prompt,
    "on_unsupported" => :on_unsupported,
    "output_compression" => :output_compression,
    "seed" => :seed,
    "style" => :style,
    "user" => :user
  }
  @reserved_option_names ~w(
    access_token api_key auth_file auth_mode fixture max_retries n oauth_file
    oauth_http_options on_finch_request quality receive_timeout req_http_options
    response_format size stream telemetry total_timeout output_format
  )

  @impl true
  def generate(%Request{} = request, opts) when is_list(opts) do
    with :ok <- supported_provider(request.provider),
         {:ok, api_key} <- api_key(opts),
         {:ok, request_opts} <- request_options(request, api_key),
         {:ok, client} <- client(opts) do
      call(request, request_opts, client, opts)
    end
  end

  def generate(_request, _opts) do
    {:error, Error.invalid_request("ReqLLM adapter input is invalid", %{adapter: @adapter_name})}
  end

  defp call(request, request_opts, client, opts) do
    started_at = System.monotonic_time(:millisecond)

    outcome =
      run_with_timeout(
        fn -> invoke(client, model_spec(request), request.prompt, request_opts) end,
        request.timeout_ms
      )

    elapsed_ms = max(System.monotonic_time(:millisecond) - started_at, 0)

    case outcome do
      {:ok, {:ok, %ReqLLM.Response{} = response}} ->
        normalize_response(request, response, elapsed_ms, now(opts))

      {:ok, {:ok, _other}} ->
        invalid_response("ReqLLM returned an invalid response")

      {:ok, {:error, error}} ->
        {:error, classify_error(error)}

      {:ok, other} ->
        {:error,
         Error.new(:adapter_contract, "ReqLLM client returned an invalid result",
           outcome: :unknown,
           details: %{adapter: @adapter_name, returned_shape: returned_shape(other)}
         )}

      {:exit, reason} ->
        {:error, client_exit(reason)}

      :timeout ->
        {:error,
         Error.timeout(%{
           adapter: @adapter_name,
           timeout_ms: request.timeout_ms,
           phase: :total
         })}
    end
  end

  defp normalize_response(request, response, elapsed_ms, generated_at) do
    with {:ok, part} <- one_binary_image(response),
         {:ok, image} <- build_image(request, part),
         {:ok, usage} <- build_usage(response),
         {:ok, provenance} <- build_provenance(request, response, part, generated_at) do
      Result.new(
        image: image,
        usage: usage,
        provenance: provenance,
        elapsed_ms: elapsed_ms,
        provider_metadata: ReqLLM.Response.call_metadata(response)
      )
    end
  end

  defp one_binary_image(response) do
    case ReqLLM.Response.images(response) do
      [%ReqLLM.Message.ContentPart{type: :image, data: bytes} = part]
      when is_binary(bytes) and bytes != <<>> ->
        {:ok, part}

      [%ReqLLM.Message.ContentPart{type: :image_url}] ->
        invalid_response("ReqLLM returned an image URL instead of image bytes")

      [] ->
        invalid_response("ReqLLM response did not contain image bytes")

      _parts ->
        invalid_response("ReqLLM response must contain exactly one image")
    end
  end

  defp build_image(request, part) do
    {width, height} = requested_dimensions(request.size)

    Image.new(
      bytes: part.data,
      media_type: part.media_type || media_type(request.output_format),
      width: width,
      height: height,
      metadata: image_metadata(part)
    )
  end

  defp build_usage(response) do
    raw = ReqLLM.Response.usage(response) || %{}

    Usage.new(
      generated_images: 1,
      input_tokens: optional_non_negative_integer(value(raw, :input_tokens)),
      output_tokens: optional_non_negative_integer(value(raw, :output_tokens)),
      total_tokens: optional_non_negative_integer(value(raw, :total_tokens)),
      total_cost: optional_non_negative_number(value(raw, :total_cost)),
      currency: usage_currency(raw),
      raw: raw
    )
  end

  defp build_provenance(request, response, part, generated_at) do
    metadata = ReqLLM.Response.call_metadata(response)

    Provenance.new(request,
      adapter: @adapter_name,
      response_id: response.id,
      revised_prompt: revised_prompt(part),
      generated_at: generated_at,
      metadata: Map.drop(metadata, [:response_id, :usage])
    )
  end

  defp request_options(request, api_key) do
    with {:ok, {canonical, provider_options}} <- split_provider_options(request.provider_options) do
      base = [
        api_key: api_key,
        response_format: :binary,
        output_format: request.output_format,
        total_timeout: request.timeout_ms,
        receive_timeout: request.timeout_ms,
        max_retries: 0
      ]

      options =
        base
        |> put_option(:size, request.size)
        |> put_option(:quality, request.quality)
        |> Keyword.merge(canonical)
        |> put_option(:provider_options, empty_to_nil(provider_options))

      {:ok, options}
    end
  end

  defp split_provider_options(options) when is_map(options) do
    case controlled_option(options) do
      nil -> split_allowed_provider_options(options)
      name -> invalid_option(name)
    end
  end

  defp split_allowed_provider_options(options) do
    Enum.reduce(options, {[], %{}}, fn {key, value}, {canonical, provider} ->
      name = to_string(key)

      case Map.get(@canonical_option_keys, name) do
        nil ->
          {canonical, Map.put(provider, name, value)}

        canonical_key ->
          normalized = canonical_option_value(canonical_key, value)
          {[{canonical_key, normalized} | canonical], provider}
      end
    end)
    |> then(fn {canonical, provider} -> {:ok, {Enum.reverse(canonical), provider}} end)
  end

  defp controlled_option(value) when is_map(value) do
    Enum.find_value(value, fn {key, child} ->
      name = key |> to_string() |> Macro.underscore() |> String.downcase()
      if name in @reserved_option_names, do: name, else: controlled_option(child)
    end)
  end

  defp controlled_option(value) when is_list(value),
    do: Enum.find_value(value, &controlled_option/1)

  defp controlled_option(_value), do: nil

  defp invalid_option(name) do
    {:error,
     Error.invalid_request("provider option #{name} is controlled by the adapter", %{
       adapter: @adapter_name,
       field: :provider_options,
       option: name
     })}
  end

  defp api_key(opts) do
    reader = Keyword.get(opts, :env_reader, &System.get_env/1)

    if is_function(reader, 1) do
      case reader.(@api_key_environment) do
        value when is_binary(value) ->
          case String.trim(value) do
            "" -> missing_api_key()
            key -> {:ok, key}
          end

        _value ->
          missing_api_key()
      end
    else
      {:error,
       Error.new(:adapter_contract, "environment reader is invalid",
         outcome: :not_started,
         details: %{adapter: @adapter_name}
       )}
    end
  rescue
    _error ->
      {:error,
       Error.new(:authentication, "OpenAI API key could not be read",
         outcome: :not_started,
         details: %{adapter: @adapter_name, environment: @api_key_environment}
       )}
  end

  defp missing_api_key do
    {:error,
     Error.new(:authentication, "OpenAI API key is not configured",
       outcome: :not_started,
       details: %{adapter: @adapter_name, environment: @api_key_environment}
     )}
  end

  defp supported_provider("openai"), do: :ok

  defp supported_provider(provider) do
    {:error,
     Error.new(:unsupported, "ReqLLM image adapter supports OpenAI only",
       outcome: :not_started,
       details: %{adapter: @adapter_name, provider: provider}
     )}
  end

  defp client(opts) do
    case Keyword.get(opts, :client, ReqLLM) do
      client when is_function(client, 3) -> {:ok, client}
      client when is_atom(client) -> ensure_client_module(client)
      _client -> invalid_client()
    end
  end

  defp ensure_client_module(client) do
    if Code.ensure_loaded?(client) and function_exported?(client, :generate_image, 3),
      do: {:ok, client},
      else: invalid_client()
  end

  defp invalid_client do
    {:error,
     Error.new(:adapter_contract, "ReqLLM client does not implement generate_image/3",
       outcome: :not_started,
       details: %{adapter: @adapter_name}
     )}
  end

  defp invoke(client, model, prompt, opts) when is_function(client, 3),
    do: client.(model, prompt, opts)

  defp invoke(client, model, prompt, opts),
    do: apply(client, :generate_image, [model, prompt, opts])

  defp run_with_timeout(fun, timeout_ms) do
    task = Task.async(fn -> safe_invoke(fun) end)

    case Task.yield(task, timeout_ms) do
      {:ok, result} -> result
      {:exit, reason} -> {:exit, reason}
      nil -> shutdown_task(task)
    end
  end

  defp safe_invoke(fun) do
    {:ok, fun.()}
  rescue
    error -> {:exit, {:exception, error.__struct__}}
  catch
    kind, reason -> {:exit, {kind, safe_reason(reason)}}
  end

  defp shutdown_task(task) do
    case Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:exit, reason}
      nil -> :timeout
    end
  end

  defp classify_error(%ReqLLM.Error.API.Timeout{} = error) do
    Error.timeout(%{
      adapter: @adapter_name,
      phase: error.kind,
      timeout_ms: error.timeout
    })
  end

  defp classify_error(%ReqLLM.Error.API.Request{} = error) do
    status = error.status

    Error.new(status_kind(status), status_message(status),
      outcome: if(is_integer(status), do: :failed, else: :unknown),
      retryable?: retryable?(error, status),
      provider_status: status,
      provider_code: provider_code(error.provider_code),
      details: %{
        adapter: @adapter_name,
        error_type: error_type(error),
        transport: not is_integer(status)
      }
    )
  end

  defp classify_error(%ReqLLM.Error.API.Response{} = error) do
    Error.new(:invalid_response, "image provider returned an invalid response",
      outcome: :failed,
      provider_status: error.status,
      details: %{adapter: @adapter_name, error_type: error_type(error)}
    )
  end

  defp classify_error(%ReqLLM.Error.Invalid.Capability{} = error) do
    Error.new(:unsupported, "image model does not support this request",
      outcome: :not_started,
      details: %{adapter: @adapter_name, error_type: error_type(error)}
    )
  end

  defp classify_error(%ReqLLM.Error.Invalid.NotImplemented{} = error) do
    Error.new(:unsupported, "image generation is not implemented for this provider",
      outcome: :not_started,
      details: %{adapter: @adapter_name, error_type: error_type(error)}
    )
  end

  defp classify_error(%module{} = error) do
    if String.starts_with?(Atom.to_string(module), "Elixir.ReqLLM.Error.Invalid") or
         String.starts_with?(Atom.to_string(module), "Elixir.ReqLLM.Error.Validation") do
      Error.invalid_request("ReqLLM rejected the image request", %{
        adapter: @adapter_name,
        error_type: error_type(error)
      })
    else
      unknown_error(error)
    end
  end

  defp classify_error(error), do: unknown_error(error)

  defp unknown_error(error) do
    Error.new(:internal, "ReqLLM image generation failed",
      outcome: :unknown,
      details: %{adapter: @adapter_name, error_type: error_type(error)}
    )
  end

  defp client_exit(reason) do
    Error.new(:internal, "ReqLLM image client stopped unexpectedly",
      outcome: :unknown,
      details: %{adapter: @adapter_name, exit: safe_reason(reason)}
    )
  end

  defp invalid_response(message) do
    {:error,
     Error.new(:invalid_response, message,
       outcome: :failed,
       details: %{adapter: @adapter_name}
     )}
  end

  defp status_kind(401), do: :authentication
  defp status_kind(403), do: :authorization
  defp status_kind(429), do: :rate_limited
  defp status_kind(status) when is_integer(status), do: :provider
  defp status_kind(_status), do: :network

  defp status_message(401), do: "image provider authentication failed"
  defp status_message(403), do: "image provider authorization failed"
  defp status_message(429), do: "image provider rate limit reached"
  defp status_message(status) when is_integer(status), do: "image provider request failed"
  defp status_message(_status), do: "image provider network request failed"

  defp retryable?(error, status) do
    cond do
      is_boolean(error.retryable) -> error.retryable
      status == 429 -> true
      is_integer(status) and status >= 500 -> true
      not is_integer(status) -> true
      true -> false
    end
  end

  defp provider_code(code) when is_atom(code), do: Atom.to_string(code)
  defp provider_code(code) when is_binary(code) and code != "", do: code
  defp provider_code(_code), do: nil

  defp model_spec(request), do: request.provider <> ":" <> request.model

  defp requested_dimensions({width, height}), do: {width, height}
  defp requested_dimensions(_size), do: {nil, nil}

  defp media_type(:png), do: "image/png"
  defp media_type(:jpeg), do: "image/jpeg"
  defp media_type(:webp), do: "image/webp"

  defp image_metadata(part) do
    case revised_prompt(part) do
      nil -> %{}
      prompt -> %{revised_prompt: prompt}
    end
  end

  defp revised_prompt(part) do
    case value(part.metadata, :revised_prompt) do
      prompt when is_binary(prompt) and prompt != "" -> prompt
      _prompt -> nil
    end
  end

  defp optional_non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp optional_non_negative_integer(_value), do: nil

  defp optional_non_negative_number(value) when is_number(value) and value >= 0, do: value
  defp optional_non_negative_number(_value), do: nil

  defp optional_currency(value) when is_binary(value) and value != "", do: value
  defp optional_currency(_value), do: nil

  defp usage_currency(raw) do
    pricing = value(raw, :pricing)
    optional_currency(value(raw, :currency) || value(pricing, :currency))
  end

  defp canonical_option_value(key, value)
       when key in [:background, :input_fidelity, :moderation, :on_unsupported, :style] and
              is_binary(value) do
    case String.downcase(value) do
      "auto" -> :auto
      "error" -> :error
      "high" -> :high
      "ignore" -> :ignore
      "low" -> :low
      "natural" -> :natural
      "opaque" -> :opaque
      "transparent" -> :transparent
      "vivid" -> :vivid
      "warn" -> :warn
      _value -> value
    end
  end

  defp canonical_option_value(_key, value), do: value

  defp put_option(options, _key, nil), do: options
  defp put_option(options, key, value), do: Keyword.put(options, key, value)

  defp empty_to_nil(map) when map_size(map) == 0, do: nil
  defp empty_to_nil(map), do: map

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(_value, _key), do: nil

  defp error_type(%module{}), do: inspect(module)
  defp error_type(value) when is_atom(value), do: Atom.to_string(value)
  defp error_type(value) when is_tuple(value), do: "tuple:#{tuple_size(value)}"
  defp error_type(value) when is_map(value), do: "map"
  defp error_type(_value), do: "other"

  defp safe_reason({kind, value}) when kind in [:exit, :throw],
    do: %{kind: kind, value: error_type(value)}

  defp safe_reason(value), do: error_type(value)

  defp returned_shape({tag, _value}) when is_atom(tag), do: "tuple:#{tag}"
  defp returned_shape(%module{}), do: "struct:#{inspect(module)}"
  defp returned_shape(value) when is_map(value), do: "map"
  defp returned_shape(value) when is_list(value), do: "list"
  defp returned_shape(value) when is_binary(value), do: "binary"
  defp returned_shape(value) when is_atom(value), do: "atom"
  defp returned_shape(_value), do: "other"

  defp now(opts) do
    opts
    |> Keyword.get(:now, DateTime.utc_now())
    |> DateTime.truncate(:microsecond)
  end
end
