defmodule Mix.Tasks.Delvetown.Image.Generate do
  @shortdoc "Generates and stages one image without publishing it"

  @moduledoc """
  Previews or confirms one manual image generation.

      mix delvetown.image.generate \\
        --key agentjido:workbench:v1 \\
        --prompt "AgentJido at a careful workbench" \\
        --caption "A new idea takes shape." \\
        --alt "A green robot works at a desk."

  The default command is a read-only preview. Add `--confirm` to make the one
  provider call and stage the result in SQLite. Image generation must be
  enabled for manual use in runtime settings.

  This task never uploads image bytes and never publishes a DelveTown post.
  A repeated confirmed command with the same key and inputs reuses the saved
  draft and does not call the provider again.
  """

  use Mix.Task

  alias JidoDelvetown.ManualImageGeneration

  @requirements ["app.start"]
  @switches [
    key: :string,
    prompt: :string,
    caption: :string,
    alt: :string,
    confirm: :boolean,
    help: :boolean
  ]
  @aliases [h: :help]

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} =
      OptionParser.parse(args, strict: @switches, aliases: @aliases)

    cond do
      options[:help] ->
        Mix.shell().info(@moduledoc)

      positional != [] or invalid != [] ->
        usage_error()

      true ->
        run_generation(options)
    end
  end

  defp run_generation(options) do
    attrs = %{
      key: required!(options, :key),
      prompt: required!(options, :prompt),
      caption: required!(options, :caption),
      alt_text: required!(options, :alt)
    }

    case ManualImageGeneration.plan(attrs) do
      {:ok, plan} ->
        Mix.shell().info("Planned image generation settings:")
        Mix.shell().info(Jason.encode!(ManualImageGeneration.estimate(plan), pretty: true))
        maybe_execute(plan, options[:confirm] == true)

      {:error, reason} ->
        Mix.raise("Could not plan image generation: #{inspect(reason)}")
    end
  end

  defp maybe_execute(_plan, false) do
    Mix.shell().info(
      "Preview only. Run the same command with --confirm to call the provider and stage the draft."
    )
  end

  defp maybe_execute(plan, true) do
    case ManualImageGeneration.execute(plan) do
      {:ok, result} ->
        Mix.shell().info("Saved generated image draft:")
        Mix.shell().info(Jason.encode!(result, pretty: true))
        Mix.shell().info("No image was uploaded and no DelveTown post was created.")

      {:error, reason} ->
        Mix.raise("Could not generate image: #{inspect(reason)}")
    end
  end

  defp required!(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and value != "" -> value
      _value -> Mix.raise("Missing --#{String.replace(Atom.to_string(key), "_", "-")}")
    end
  end

  defp usage_error do
    Mix.raise(
      "Use: mix delvetown.image.generate --key KEY --prompt TEXT --caption TEXT --alt TEXT [--confirm]"
    )
  end
end
