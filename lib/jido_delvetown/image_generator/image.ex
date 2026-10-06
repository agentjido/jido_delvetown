defmodule JidoDelvetown.ImageGenerator.Image do
  @moduledoc "One generated image with byte and media integrity metadata."

  alias JidoDelvetown.ImageGenerator.Error

  @type t :: %__MODULE__{
          bytes: binary(),
          byte_size: pos_integer(),
          digest: String.t(),
          media_type: String.t(),
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          metadata: map()
        }

  @enforce_keys [:bytes, :byte_size, :digest, :media_type]
  defstruct bytes: nil,
            byte_size: nil,
            digest: nil,
            media_type: nil,
            width: nil,
            height: nil,
            metadata: %{}

  @doc "Builds a byte-backed generated image."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: attrs |> Map.new() |> new(),
      else: invalid(:image, "must be a map")
  end

  def new(attrs) when is_map(attrs) do
    with {:ok, bytes} <- validate_bytes(value(attrs, :bytes)),
         {:ok, media_type} <- validate_media_type(value(attrs, :media_type)),
         {:ok, {width, height}} <-
           validate_dimensions(value(attrs, :width), value(attrs, :height)),
         {:ok, metadata} <- validate_metadata(value(attrs, :metadata, %{})) do
      {:ok,
       %__MODULE__{
         bytes: bytes,
         byte_size: byte_size(bytes),
         digest: digest(bytes),
         media_type: media_type,
         width: width,
         height: height,
         metadata: metadata
       }}
    end
  end

  def new(_attrs), do: invalid(:image, "must be a map")

  @doc "Validates the byte size and digest stored with an image."
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = image) do
    cond do
      not is_binary(image.bytes) or image.bytes == <<>> -> {:error, :missing_image_bytes}
      image.byte_size != byte_size(image.bytes) -> {:error, :invalid_image_byte_size}
      image.digest != digest(image.bytes) -> {:error, :invalid_image_digest}
      not valid_media_type?(image.media_type) -> {:error, :invalid_image_media_type}
      not valid_dimensions?(image.width, image.height) -> {:error, :invalid_image_dimensions}
      not is_map(image.metadata) -> {:error, :invalid_image_metadata}
      true -> :ok
    end
  end

  @doc "Returns the lowercase SHA-256 digest for image bytes."
  @spec digest(binary()) :: String.t()
  def digest(bytes) when is_binary(bytes) do
    bytes |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  defp validate_bytes(bytes) when is_binary(bytes) and bytes != <<>>, do: {:ok, bytes}
  defp validate_bytes(_bytes), do: invalid(:bytes, "must contain image bytes")

  defp validate_media_type(media_type) when is_binary(media_type) do
    media_type = media_type |> String.trim() |> String.downcase()

    if valid_media_type?(media_type),
      do: {:ok, media_type},
      else: invalid(:media_type, "must be an image MIME type")
  end

  defp validate_media_type(_media_type), do: invalid(:media_type, "must be an image MIME type")

  defp valid_media_type?("image/" <> subtype), do: subtype != ""
  defp valid_media_type?(_media_type), do: false

  defp validate_dimensions(width, height) do
    if valid_dimensions?(width, height),
      do: {:ok, {width, height}},
      else: invalid(:dimensions, "must be positive and set together")
  end

  defp valid_dimensions?(nil, nil), do: true

  defp valid_dimensions?(width, height),
    do: is_integer(width) and width > 0 and is_integer(height) and height > 0

  defp validate_metadata(metadata) when is_map(metadata), do: {:ok, metadata}
  defp validate_metadata(_metadata), do: invalid(:metadata, "must be a map")

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
