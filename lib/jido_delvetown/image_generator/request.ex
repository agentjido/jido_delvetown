defmodule JidoDelvetown.ImageGenerator.Request do
  @moduledoc "Validated, provider-neutral input for one generated image."

  alias JidoDelvetown.ImageGenerator.Error

  @default_timeout_ms 120_000
  @min_timeout_ms 1_000
  @max_timeout_ms 600_000
  @max_prompt_bytes 32_000
  @max_dimension 16_384
  @output_formats [:png, :jpeg, :webp]

  @type size :: :auto | {pos_integer(), pos_integer()} | nil
  @type output_format :: :png | :jpeg | :webp

  @type t :: %__MODULE__{
          prompt: String.t(),
          provider: String.t(),
          model: String.t(),
          size: size(),
          quality: String.t() | nil,
          output_format: output_format(),
          timeout_ms: pos_integer(),
          provider_options: map(),
          metadata: map()
        }

  @enforce_keys [:prompt, :provider, :model]
  defstruct prompt: nil,
            provider: nil,
            model: nil,
            size: nil,
            quality: nil,
            output_format: :png,
            timeout_ms: @default_timeout_ms,
            provider_options: %{},
            metadata: %{}

  @doc "Returns the default total call timeout in milliseconds."
  @spec default_timeout_ms() :: pos_integer()
  def default_timeout_ms, do: @default_timeout_ms

  @doc "Builds and validates a generation request."
  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = request), do: request |> Map.from_struct() |> new()

  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: attrs |> Map.new() |> new(),
      else: invalid(:request, "must be a map")
  end

  def new(attrs) when is_map(attrs) do
    with {:ok, prompt} <- required_text(attrs, :prompt, @max_prompt_bytes),
         {:ok, provider} <- required_text(attrs, :provider, 100),
         {:ok, model} <- required_text(attrs, :model, 255),
         {:ok, size} <- normalize_size(value(attrs, :size)),
         {:ok, quality} <- optional_text(value(attrs, :quality), :quality, 64),
         {:ok, output_format} <- normalize_output_format(value(attrs, :output_format, :png)),
         {:ok, timeout_ms} <- normalize_timeout(value(attrs, :timeout_ms, @default_timeout_ms)),
         {:ok, provider_options} <-
           require_map(value(attrs, :provider_options, %{}), :provider_options),
         {:ok, metadata} <- require_map(value(attrs, :metadata, %{}), :metadata) do
      {:ok,
       %__MODULE__{
         prompt: prompt,
         provider: provider,
         model: model,
         size: size,
         quality: quality,
         output_format: output_format,
         timeout_ms: timeout_ms,
         provider_options: provider_options,
         metadata: metadata
       }}
    end
  end

  def new(_attrs), do: invalid(:request, "must be a map")

  @doc "Returns a stable hash of the provider-visible request and timeout budget."
  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{} = request) do
    request
    |> semantic_map()
    |> canonical_term()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "Returns the request fields that can affect the remote operation."
  @spec semantic_map(t()) :: map()
  def semantic_map(%__MODULE__{} = request) do
    Map.take(request, [
      :prompt,
      :provider,
      :model,
      :size,
      :quality,
      :output_format,
      :timeout_ms,
      :provider_options
    ])
  end

  defp required_text(attrs, key, max_bytes) do
    case value(attrs, key) do
      text when is_binary(text) ->
        text = String.trim(text)

        cond do
          text == "" -> invalid(key, "must not be empty")
          byte_size(text) > max_bytes -> invalid(key, "is too long")
          true -> {:ok, text}
        end

      value when is_atom(value) and key == :provider ->
        required_text(Map.put(attrs, key, Atom.to_string(value)), key, max_bytes)

      _other ->
        invalid(key, "must be text")
    end
  end

  defp optional_text(nil, _key, _max_bytes), do: {:ok, nil}

  defp optional_text(value, key, max_bytes) when is_atom(value) do
    optional_text(Atom.to_string(value), key, max_bytes)
  end

  defp optional_text(value, key, max_bytes) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> invalid(key, "must not be empty")
      byte_size(value) > max_bytes -> invalid(key, "is too long")
      true -> {:ok, value}
    end
  end

  defp optional_text(_value, key, _max_bytes), do: invalid(key, "must be text")

  defp normalize_size(nil), do: {:ok, nil}
  defp normalize_size(:auto), do: {:ok, :auto}
  defp normalize_size("auto"), do: {:ok, :auto}

  defp normalize_size({width, height}), do: validate_dimensions(width, height)

  defp normalize_size(size) when is_binary(size) do
    case Regex.run(~r/\A([1-9]\d*)x([1-9]\d*)\z/, String.trim(size)) do
      [_size, width, height] ->
        validate_dimensions(String.to_integer(width), String.to_integer(height))

      _other ->
        invalid(:size, "must be auto or WIDTHxHEIGHT")
    end
  end

  defp normalize_size(_size), do: invalid(:size, "must be auto or a width and height pair")

  defp validate_dimensions(width, height)
       when is_integer(width) and width in 1..@max_dimension and is_integer(height) and
              height in 1..@max_dimension,
       do: {:ok, {width, height}}

  defp validate_dimensions(_width, _height),
    do: invalid(:size, "dimensions must be from 1 through #{@max_dimension}")

  defp normalize_output_format(format) when is_atom(format) and format in @output_formats,
    do: {:ok, format}

  defp normalize_output_format(format) when is_binary(format) do
    case String.downcase(String.trim(format)) do
      "png" -> {:ok, :png}
      "jpeg" -> {:ok, :jpeg}
      "jpg" -> {:ok, :jpeg}
      "webp" -> {:ok, :webp}
      _other -> invalid(:output_format, "must be png, jpeg, or webp")
    end
  end

  defp normalize_output_format(_format),
    do: invalid(:output_format, "must be png, jpeg, or webp")

  defp normalize_timeout(timeout_ms)
       when is_integer(timeout_ms) and timeout_ms in @min_timeout_ms..@max_timeout_ms,
       do: {:ok, timeout_ms}

  defp normalize_timeout(_timeout_ms) do
    invalid(:timeout_ms, "must be from #{@min_timeout_ms} through #{@max_timeout_ms}")
  end

  defp require_map(value, _key) when is_map(value), do: {:ok, value}
  defp require_map(_value, key), do: invalid(key, "must be a map")

  defp value(attrs, key, default \\ nil) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key), default)
    end
  end

  defp invalid(field, reason) do
    {:error, Error.invalid_request("#{field} #{reason}", %{field: field, reason: reason})}
  end

  defp canonical_term(value) when is_map(value) do
    value
    |> Enum.map(fn {key, child} -> {to_string(key), canonical_term(child)} end)
    |> Enum.sort()
  end

  defp canonical_term(value) when is_list(value), do: Enum.map(value, &canonical_term/1)

  defp canonical_term(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> canonical_term()

  defp canonical_term(value), do: value
end
