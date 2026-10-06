defmodule Mix.Tasks.Delvetown.Image.StageSelfPortrait do
  @shortdoc "Stages the fixed AgentJido self-portrait without publishing it"

  @moduledoc """
  Stages the reviewed AgentJido self-portrait in local SQLite.

      mix delvetown.image.stage_self_portrait

  The task verifies the fixed asset digest. It does not upload a blob or create
  a DelveTown post. Review the result in the dashboard Image drafts tab.
  """

  use Mix.Task

  alias JidoDelvetown.SelfPortraitDraft

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    case args do
      [] -> stage!()
      ["--help"] -> Mix.shell().info(@moduledoc)
      _args -> Mix.raise("Use: mix delvetown.image.stage_self_portrait")
    end
  end

  defp stage! do
    case SelfPortraitDraft.stage() do
      {:ok, result} ->
        output = %{
          draft_key: result.draft.key,
          artifact_digest: result.artifact.digest,
          mime_type: result.artifact.mime_type,
          dimensions: [result.artifact.width, result.artifact.height],
          byte_size: result.artifact.byte_size,
          caption: result.draft.caption,
          alt_text: result.draft.alt_text,
          state: result.draft.state,
          reused?: result.reused?
        }

        Mix.shell().info(Jason.encode!(output, pretty: true))
        Mix.shell().info("Staged locally. No blob was uploaded and no post was created.")

      {:error, reason} ->
        Mix.raise("Could not stage the AgentJido self-portrait: #{inspect(reason)}")
    end
  end
end
