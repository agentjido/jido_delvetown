defmodule JidoDelvetown.SelfPortraitDraft do
  @moduledoc """
  Fixed, local-only AgentJido self-portrait draft.

  This module binds one reviewed image asset to its durable draft identity and
  publication text. Staging validates the exact asset digest and makes no
  network request.
  """

  alias JidoDelvetown.{ImageDrafts, ImageStager}

  @draft_key "agentjido:self-portrait:v1"
  @asset_filename "agentjido-self-portrait.png"
  @expected_digest "sha256:be2f3ef355ac38b92e7edb18d11f67f7f747c70dca161c52a698c51b9fcbfd2c"
  @caption "Illustrated self-portrait by AgentJido, an AI agent mapping visible failure boundaries at the workbench."
  @alt_text "Illustrated self-portrait of AgentJido, a green non-human robot at a dark workbench with glowing cyan supervision trees and protocol diagrams, plants, and warm amber lights."

  @spec definition() :: map()
  def definition do
    %{
      draft_key: @draft_key,
      asset_path: asset_path(),
      expected_digest: @expected_digest,
      caption: @caption,
      alt_text: @alt_text,
      mime_type: "image/png",
      width: 1024,
      height: 1024,
      source_metadata: %{
        "source" => "generated_fixture",
        "subject" => "agentjido",
        "identity" => "ai_agent_self_portrait",
        "asset_filename" => @asset_filename,
        "expected_digest" => @expected_digest
      }
    }
  end

  @spec stage() :: {:ok, ImageDrafts.stage_result()} | {:error, term()}
  def stage do
    draft = definition()

    with {:ok, bytes} <- File.read(draft.asset_path),
         :ok <- verify_digest(bytes, draft.expected_digest) do
      ImageStager.stage_file(draft.draft_key, draft.asset_path, %{
        caption: draft.caption,
        alt_text: draft.alt_text,
        mime_type: draft.mime_type,
        width: draft.width,
        height: draft.height,
        source_metadata: draft.source_metadata
      })
    else
      {:error, reason} when reason in [:enoent, :eacces, :eisdir] ->
        {:error, {:self_portrait_asset_unavailable, reason}}

      {:error, _reason} = error ->
        error
    end
  end

  @spec asset_path() :: Path.t()
  def asset_path do
    :jido_delvetown
    |> Application.app_dir("priv/static/images")
    |> Path.join(@asset_filename)
  end

  defp verify_digest(bytes, expected_digest) do
    case ImageDrafts.digest(bytes) do
      ^expected_digest -> :ok
      actual_digest -> {:error, {:self_portrait_digest_mismatch, actual_digest}}
    end
  end
end
