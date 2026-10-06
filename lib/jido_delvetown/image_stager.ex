defmodule JidoDelvetown.ImageStager do
  @moduledoc """
  Stages image post drafts without making a network request.

  Generated image flows can call `stage_bytes/3`. Operators can use
  `stage_file/3` directly or through the `mix delvetown.image.stage` task.
  Both paths use the same durable draft contract.
  """

  alias JidoDelvetown.ImageDrafts
  alias JidoDelvetown.ImagePostContract

  @mime_types_by_extension %{
    ".avif" => "image/avif",
    ".gif" => "image/gif",
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp"
  }
  @accepted_mime_types Map.values(@mime_types_by_extension) |> Enum.uniq()

  @spec stage_bytes(String.t(), binary(), map()) ::
          {:ok, ImageDrafts.stage_result()} | {:error, term()}
  def stage_bytes(draft_key, bytes, attrs), do: ImageDrafts.stage(draft_key, bytes, attrs)

  @spec stage_file(String.t(), Path.t(), map()) ::
          {:ok, ImageDrafts.stage_result()} | {:error, term()}
  def stage_file(draft_key, path, attrs)
      when is_binary(draft_key) and is_binary(path) and is_map(attrs) do
    expanded_path = Path.expand(path)

    with {:ok, stat} <- File.stat(expanded_path),
         :ok <- validate_file(stat),
         :ok <- validate_file_size(stat.size),
         {:ok, mime_type} <- mime_type(attrs, expanded_path),
         {:ok, source_metadata} <- source_metadata(attrs, expanded_path),
         {:ok, bytes} <- File.read(expanded_path) do
      attrs =
        attrs
        |> put_attr(:mime_type, mime_type)
        |> put_attr(:source_metadata, source_metadata)

      stage_bytes(draft_key, bytes, attrs)
    else
      {:error, reason} when reason in [:enoent, :eacces, :eisdir] ->
        {:error, {:image_file_unavailable, reason}}

      {:error, _reason} = error ->
        error
    end
  end

  def stage_file(_draft_key, _path, _attrs), do: {:error, :invalid_stage_file_request}

  defp validate_file(%File.Stat{type: :regular}), do: :ok
  defp validate_file(%File.Stat{}), do: {:error, :image_path_not_regular_file}

  defp validate_file_size(size) do
    cond do
      size == 0 -> {:error, :empty_image}
      size > ImagePostContract.max_blob_bytes() -> {:error, :image_too_large}
      true -> :ok
    end
  end

  defp mime_type(attrs, path) do
    extension = path |> Path.extname() |> String.downcase()

    case attr(attrs, :mime_type) || Map.get(@mime_types_by_extension, extension) do
      mime_type when mime_type in @accepted_mime_types -> {:ok, mime_type}
      _mime_type -> {:error, :unsupported_mime_type}
    end
  end

  defp source_metadata(attrs, path) do
    case attr(attrs, :source_metadata, %{}) do
      metadata when is_map(metadata) ->
        source = Map.get(metadata, :source, Map.get(metadata, "source", "local_file"))

        filename =
          Map.get(metadata, :filename, Map.get(metadata, "filename", Path.basename(path)))

        metadata =
          metadata
          |> Map.drop([:source, :filename])
          |> Map.put_new("source", source)
          |> Map.put_new("filename", filename)

        {:ok, metadata}

      _metadata ->
        {:error, :invalid_source_metadata}
    end
  end

  defp put_attr(attrs, key, value) do
    if Map.has_key?(attrs, Atom.to_string(key)),
      do: Map.put(attrs, Atom.to_string(key), value),
      else: Map.put(attrs, key, value)
  end

  defp attr(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
