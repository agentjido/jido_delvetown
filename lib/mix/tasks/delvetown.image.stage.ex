defmodule Mix.Tasks.Delvetown.Image.Stage do
  @shortdoc "Stages a local image for DelveTown review"

  @moduledoc """
  Stages one local image in SQLite. This task does not upload or publish it.

      mix delvetown.image.stage \
        --key agentjido:self-portrait \
        --file ./self-portrait.png \
        --caption "AgentJido, at the workbench." \
        --alt "A green robot working at a desk." \
        --width 1024 \
        --height 1024

  The MIME type is inferred from the file extension. Use `--mime-type` to set
  it explicitly. Width and height are optional, but must be given together.
  """

  use Mix.Task

  alias JidoDelvetown.ImageStager

  @requirements ["app.start"]
  @switches [
    key: :string,
    file: :string,
    caption: :string,
    alt: :string,
    mime_type: :string,
    width: :integer,
    height: :integer,
    help: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      options[:help] ->
        Mix.shell().info(@moduledoc)

      positional != [] or invalid != [] ->
        usage_error()

      true ->
        stage!(options)
    end
  end

  defp stage!(options) do
    key = required!(options, :key)
    path = required!(options, :file)
    caption = required!(options, :caption)
    alt_text = required!(options, :alt)
    {width, height} = dimensions!(options)

    attrs = %{
      caption: caption,
      alt_text: alt_text,
      mime_type: options[:mime_type],
      width: width,
      height: height,
      source_metadata: %{"entry_point" => "mix delvetown.image.stage"}
    }

    case ImageStager.stage_file(key, path, attrs) do
      {:ok, result} ->
        output = %{
          draft_key: result.draft.key,
          artifact_digest: result.artifact.digest,
          mime_type: result.artifact.mime_type,
          byte_size: result.artifact.byte_size,
          state: result.draft.state,
          reused?: result.reused?
        }

        Mix.shell().info(Jason.encode!(output, pretty: true))
        Mix.shell().info("Staged locally. No blob was uploaded and no post was created.")

      {:error, reason} ->
        Mix.raise("Could not stage image: #{inspect(reason)}")
    end
  end

  defp required!(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and value != "" -> value
      _value -> Mix.raise("Missing --#{String.replace(Atom.to_string(key), "_", "-")}")
    end
  end

  defp dimensions!(options) do
    case {options[:width], options[:height]} do
      {nil, nil} -> {nil, nil}
      {width, height} when is_integer(width) and is_integer(height) -> {width, height}
      _other -> Mix.raise("Set both --width and --height, or set neither")
    end
  end

  defp usage_error do
    Mix.raise("Use: mix delvetown.image.stage --key KEY --file PATH --caption TEXT --alt TEXT")
  end
end
