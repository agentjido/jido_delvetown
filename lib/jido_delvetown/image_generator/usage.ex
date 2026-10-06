defmodule JidoDelvetown.ImageGenerator.Usage do
  @moduledoc "Provider-neutral usage and cost data for one generation call."

  alias JidoDelvetown.ImageGenerator.Error

  @type t :: %__MODULE__{
          generated_images: pos_integer(),
          input_tokens: non_neg_integer() | nil,
          output_tokens: non_neg_integer() | nil,
          total_tokens: non_neg_integer() | nil,
          total_cost: number() | nil,
          currency: String.t() | nil,
          raw: map()
        }

  @enforce_keys [:generated_images]
  defstruct generated_images: 1,
            input_tokens: nil,
            output_tokens: nil,
            total_tokens: nil,
            total_cost: nil,
            currency: nil,
            raw: %{}

  @doc "Builds normalized usage while retaining safe provider usage in `raw`."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs \\ %{})

  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: attrs |> Map.new() |> new(),
      else: invalid(:usage, "must be a map")
  end

  def new(attrs) when is_map(attrs) do
    with {:ok, generated_images} <-
           positive_integer(value(attrs, :generated_images, 1), :generated_images),
         {:ok, input_tokens} <- optional_integer(value(attrs, :input_tokens), :input_tokens),
         {:ok, output_tokens} <- optional_integer(value(attrs, :output_tokens), :output_tokens),
         {:ok, total_tokens} <- optional_integer(value(attrs, :total_tokens), :total_tokens),
         {:ok, total_cost} <- optional_cost(value(attrs, :total_cost)),
         {:ok, currency} <- optional_currency(value(attrs, :currency)),
         {:ok, raw} <- raw_map(value(attrs, :raw, %{})) do
      {:ok,
       %__MODULE__{
         generated_images: generated_images,
         input_tokens: input_tokens,
         output_tokens: output_tokens,
         total_tokens: total_tokens,
         total_cost: total_cost,
         currency: currency,
         raw: raw
       }}
    end
  end

  def new(_attrs), do: invalid(:usage, "must be a map")

  @doc "Validates normalized usage values."
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = usage) do
    if is_integer(usage.generated_images) and usage.generated_images > 0 and
         Enum.all?(
           [usage.input_tokens, usage.output_tokens, usage.total_tokens],
           &valid_optional_integer?/1
         ) and
         valid_optional_cost?(usage.total_cost) and valid_optional_currency?(usage.currency) and
         is_map(usage.raw) do
      :ok
    else
      {:error, :invalid_usage}
    end
  end

  defp positive_integer(value, _field) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_value, field), do: invalid(field, "must be a positive integer")

  defp optional_integer(nil, _field), do: {:ok, nil}
  defp optional_integer(value, _field) when is_integer(value) and value >= 0, do: {:ok, value}
  defp optional_integer(_value, field), do: invalid(field, "must be a non-negative integer")

  defp optional_cost(nil), do: {:ok, nil}
  defp optional_cost(value) when is_number(value) and value >= 0, do: {:ok, value}
  defp optional_cost(_value), do: invalid(:total_cost, "must be a non-negative number")

  defp optional_currency(nil), do: {:ok, nil}

  defp optional_currency(value) when is_binary(value) do
    value = value |> String.trim() |> String.upcase()
    if value == "", do: invalid(:currency, "must not be empty"), else: {:ok, value}
  end

  defp optional_currency(_value), do: invalid(:currency, "must be text")

  defp raw_map(value) when is_map(value), do: {:ok, value}
  defp raw_map(_value), do: invalid(:raw, "must be a map")

  defp valid_optional_integer?(nil), do: true
  defp valid_optional_integer?(value), do: is_integer(value) and value >= 0
  defp valid_optional_cost?(nil), do: true
  defp valid_optional_cost?(value), do: is_number(value) and value >= 0
  defp valid_optional_currency?(nil), do: true
  defp valid_optional_currency?(value), do: is_binary(value) and value != ""

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
