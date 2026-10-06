defmodule JidoDelvetown.ImageGenerator do
  @moduledoc """
  Provider-neutral boundary for one image generation call.

  A generator receives a validated `JidoDelvetown.ImageGenerator.Request` and
  returns one byte-backed `JidoDelvetown.ImageGenerator.Result`. It does not
  persist a request, stage a draft, upload a blob, or publish a post.

  Implementations must apply `request.timeout_ms` as the total call budget. A
  timeout is an unknown remote outcome because the provider can finish after
  the local caller stops waiting.
  """

  alias JidoDelvetown.ImageGenerator.{Error, Request, Result}

  @typedoc "Runtime-only adapter options. They must not change request semantics."
  @type adapter_options :: keyword()

  @callback generate(Request.t(), adapter_options()) ::
              {:ok, Result.t()} | {:error, Error.t()}

  @doc "Validates a request and runs one generator adapter."
  @spec generate(module(), Request.t() | map() | keyword(), adapter_options()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def generate(generator, request, opts \\ [])

  def generate(generator, request, opts) when is_atom(generator) and is_list(opts) do
    with {:ok, request} <- Request.new(request),
         :ok <- ensure_adapter(generator) do
      generator
      |> apply(:generate, [request, opts])
      |> normalize_adapter_result(generator)
    end
  end

  def generate(_generator, _request, _opts) do
    {:error,
     Error.invalid_request("generator and adapter options are invalid", %{
       field: :generator
     })}
  end

  defp ensure_adapter(generator) do
    if Code.ensure_loaded?(generator) and function_exported?(generator, :generate, 2) do
      :ok
    else
      {:error,
       Error.new(:adapter_contract, "generator does not implement generate/2",
         outcome: :not_started,
         details: %{generator: inspect(generator)}
       )}
    end
  end

  defp normalize_adapter_result({:ok, %Result{} = result}, _generator) do
    case Result.validate(result) do
      :ok -> {:ok, result}
      {:error, reason} -> {:error, invalid_adapter_result(reason)}
    end
  end

  defp normalize_adapter_result({:error, %Error{} = error}, _generator) do
    case Error.validate(error) do
      :ok -> {:error, error}
      {:error, reason} -> {:error, invalid_adapter_result(reason)}
    end
  end

  defp normalize_adapter_result(other, generator) do
    {:error,
     Error.new(:adapter_contract, "generator returned an invalid result",
       outcome: :unknown,
       details: %{generator: inspect(generator), returned_shape: returned_shape(other)}
     )}
  end

  defp invalid_adapter_result(reason) do
    Error.new(:adapter_contract, "generator returned an invalid result",
      outcome: :unknown,
      details: %{reason: reason}
    )
  end

  defp returned_shape({tag, _value}) when is_atom(tag), do: "tuple:#{tag}"
  defp returned_shape(%module{}), do: "struct:#{inspect(module)}"
  defp returned_shape(value) when is_map(value), do: "map"
  defp returned_shape(value) when is_list(value), do: "list"
  defp returned_shape(value) when is_binary(value), do: "binary"
  defp returned_shape(value) when is_atom(value), do: "atom"
  defp returned_shape(_value), do: "other"
end
