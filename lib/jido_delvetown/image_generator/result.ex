defmodule JidoDelvetown.ImageGenerator.Result do
  @moduledoc "Validated output from one image generator call."

  alias JidoDelvetown.ImageGenerator.{Error, Image, Provenance, Usage}

  @type t :: %__MODULE__{
          image: Image.t(),
          usage: Usage.t(),
          provenance: Provenance.t(),
          elapsed_ms: non_neg_integer() | nil,
          provider_metadata: map()
        }

  @enforce_keys [:image, :usage, :provenance]
  defstruct image: nil,
            usage: nil,
            provenance: nil,
            elapsed_ms: nil,
            provider_metadata: %{}

  @doc "Builds a validated generation result."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: attrs |> Map.new() |> new(),
      else: invalid(:result, "must be a map")
  end

  def new(attrs) when is_map(attrs) do
    with {:ok, image} <- require_struct(value(attrs, :image), Image, :image),
         {:ok, usage} <- require_struct(value(attrs, :usage), Usage, :usage),
         {:ok, provenance} <- require_struct(value(attrs, :provenance), Provenance, :provenance),
         {:ok, elapsed_ms} <- elapsed_ms(value(attrs, :elapsed_ms)),
         {:ok, provider_metadata} <- provider_metadata(value(attrs, :provider_metadata, %{})) do
      result = %__MODULE__{
        image: image,
        usage: usage,
        provenance: provenance,
        elapsed_ms: elapsed_ms,
        provider_metadata: provider_metadata
      }

      case validate(result) do
        :ok -> {:ok, result}
        {:error, reason} -> invalid(:result, inspect(reason))
      end
    end
  end

  def new(_attrs), do: invalid(:result, "must be a map")

  @doc "Validates all nested result values and safe provider metadata."
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = result) do
    with :ok <- Image.validate(result.image),
         :ok <- Usage.validate(result.usage),
         :ok <- Provenance.validate(result.provenance),
         :ok <- validate_elapsed(result.elapsed_ms),
         true <- is_map(result.provider_metadata) do
      :ok
    else
      false -> {:error, :invalid_provider_metadata}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_struct(%module{} = value, module, _field), do: {:ok, value}
  defp require_struct(_value, _module, field), do: invalid(field, "has the wrong type")

  defp elapsed_ms(nil), do: {:ok, nil}
  defp elapsed_ms(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp elapsed_ms(_value), do: invalid(:elapsed_ms, "must be a non-negative integer")

  defp provider_metadata(value) when is_map(value), do: {:ok, value}
  defp provider_metadata(_value), do: invalid(:provider_metadata, "must be a map")

  defp validate_elapsed(nil), do: :ok
  defp validate_elapsed(value) when is_integer(value) and value >= 0, do: :ok
  defp validate_elapsed(_value), do: {:error, :invalid_elapsed_ms}

  defp value(attrs, key, default \\ nil) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key), default)
    end
  end

  defp invalid(field, reason) do
    {:error,
     Error.new(:invalid_response, "#{field} #{reason}", details: %{field: field, reason: reason})}
  end
end
