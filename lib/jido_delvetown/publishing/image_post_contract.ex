defmodule JidoDelvetown.ImagePostContract do
  @moduledoc """
  Validates the DelveTown wire contract for an image post record.

  This module describes the remote lexicon. Local draft policy can be stricter.
  """

  alias ProtoRune.CID

  @post_type "town.delve.feed.post"
  @embed_type "town.delve.embed.images"
  @blob_type "blob"
  @max_images 4
  @max_blob_bytes 2_000_000

  @type error ::
          :invalid_post
          | :invalid_post_type
          | :missing_image_embed
          | :invalid_embed_type
          | :invalid_images
          | :too_many_images
          | {:invalid_image, non_neg_integer(), term()}

  @spec post_type() :: String.t()
  def post_type, do: @post_type

  @spec embed_type() :: String.t()
  def embed_type, do: @embed_type

  @spec max_images() :: pos_integer()
  def max_images, do: @max_images

  @spec max_blob_bytes() :: pos_integer()
  def max_blob_bytes, do: @max_blob_bytes

  @doc """
  Validates the image-specific fields in a `town.delve.feed.post` record.

  The function accepts wire JSON keys and the snake-case atom keys returned by
  the configured protocol transport.
  """
  @spec validate(map()) :: :ok | {:error, error()}
  def validate(record) when is_map(record) do
    with :ok <- require_type(record, @post_type, :invalid_post_type),
         {:ok, embed} <- fetch_map(record, :embed, "embed", :missing_image_embed),
         :ok <- require_type(embed, @embed_type, :invalid_embed_type),
         {:ok, images} <- fetch_images(embed),
         :ok <- validate_image_count(images) do
      validate_images(images)
    end
  end

  def validate(_record), do: {:error, :invalid_post}

  @doc "Validates one AT Protocol image blob reference."
  @spec validate_blob(map()) :: :ok | {:error, atom()}
  def validate_blob(blob) when is_map(blob) do
    with :ok <- require_type(blob, @blob_type, :invalid_blob_type),
         :ok <- validate_blob_ref(field(blob, :ref, "ref")),
         :ok <- validate_mime_type(field(blob, :mime_type, "mimeType")),
         :ok <- validate_blob_size(field(blob, :size, "size")) do
      :ok
    end
  end

  def validate_blob(_blob), do: {:error, :invalid_blob}

  defp fetch_images(embed) do
    case field(embed, :images, "images") do
      images when is_list(images) -> {:ok, images}
      _other -> {:error, :invalid_images}
    end
  end

  defp validate_image_count(images) when length(images) <= @max_images, do: :ok
  defp validate_image_count(_images), do: {:error, :too_many_images}

  defp validate_images(images) do
    images
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {image, index}, :ok ->
      case validate_image(image) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_image, index, reason}}}
      end
    end)
  end

  defp validate_image(image) when is_map(image) do
    with {:ok, blob} <- fetch_map(image, :image, "image", :missing_blob),
         :ok <- validate_blob(blob),
         :ok <- validate_alt(field(image, :alt, "alt")),
         :ok <- validate_aspect_ratio(field(image, :aspect_ratio, "aspectRatio")) do
      :ok
    end
  end

  defp validate_image(_image), do: {:error, :invalid_image_entry}

  defp validate_blob_ref(ref) when is_map(ref) do
    case field(ref, :"$link", "$link") do
      cid when is_binary(cid) -> validate_cid(cid)
      _other -> {:error, :invalid_blob_ref}
    end
  end

  defp validate_blob_ref(_ref), do: {:error, :invalid_blob_ref}

  defp validate_cid(cid) do
    case CID.from_string(cid) do
      {:ok, _cid} -> :ok
      {:error, _reason} -> {:error, :invalid_blob_ref}
    end
  end

  defp validate_mime_type("image/" <> subtype) when byte_size(subtype) > 0, do: :ok
  defp validate_mime_type(_mime_type), do: {:error, :unsupported_mime_type}

  defp validate_blob_size(size)
       when is_integer(size) and size >= 0 and size <= @max_blob_bytes,
       do: :ok

  defp validate_blob_size(size) when is_integer(size) and size > @max_blob_bytes,
    do: {:error, :blob_too_large}

  defp validate_blob_size(_size), do: {:error, :invalid_blob_size}

  defp validate_alt(alt) when is_binary(alt), do: :ok
  defp validate_alt(_alt), do: {:error, :invalid_alt}

  defp validate_aspect_ratio(nil), do: :ok

  defp validate_aspect_ratio(aspect_ratio) when is_map(aspect_ratio) do
    width = field(aspect_ratio, :width, "width")
    height = field(aspect_ratio, :height, "height")

    if is_integer(width) and width >= 1 and is_integer(height) and height >= 1,
      do: :ok,
      else: {:error, :invalid_aspect_ratio}
  end

  defp validate_aspect_ratio(_aspect_ratio), do: {:error, :invalid_aspect_ratio}

  defp require_type(map, expected, error) do
    if field(map, :"$type", "$type") == expected, do: :ok, else: {:error, error}
  end

  defp fetch_map(map, atom_key, string_key, error) do
    case field(map, atom_key, string_key) do
      value when is_map(value) -> {:ok, value}
      _other -> {:error, error}
    end
  end

  defp field(map, atom_key, string_key) do
    case Map.fetch(map, atom_key) do
      {:ok, value} -> value
      :error -> Map.get(map, string_key)
    end
  end
end
