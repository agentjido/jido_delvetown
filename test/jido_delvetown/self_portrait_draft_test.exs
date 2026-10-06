defmodule JidoDelvetown.SelfPortraitDraftTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{ImageDrafts, ImagePostContract, ImagePublisher, Inspection, Repo}
  alias JidoDelvetown.SelfPortraitDraft
  alias JidoDelvetown.Storage.{ImageArtifact, ImageDraft}

  @cid "bafkreid2wtyqjcrjwqf7vqumwnnhjq73hlk2h335lxspj6ftcgw7net53a"

  setup do
    Repo.delete_all(ImageDraft)
    Repo.delete_all(ImageArtifact)

    on_exit(fn ->
      Repo.delete_all(ImageDraft)
      Repo.delete_all(ImageArtifact)
    end)

    :ok
  end

  test "binds the reviewed AgentJido image and identity copy to one stable draft" do
    definition = SelfPortraitDraft.definition()

    assert definition.draft_key == "agentjido:self-portrait:v1"

    assert definition.expected_digest ==
             "sha256:be2f3ef355ac38b92e7edb18d11f67f7f747c70dca161c52a698c51b9fcbfd2c"

    assert definition.mime_type == "image/png"
    assert definition.width == 1024
    assert definition.height == 1024
    assert definition.caption =~ "Illustrated self-portrait by AgentJido"
    assert definition.caption =~ "AI agent"
    assert definition.alt_text =~ "green non-human robot"
    refute definition.caption =~ "Mike"
    refute definition.alt_text =~ "Mike"
    assert File.regular?(definition.asset_path)

    assert {:ok, staged} = SelfPortraitDraft.stage()
    assert staged.draft.key == definition.draft_key
    assert staged.draft.caption == definition.caption
    assert staged.draft.alt_text == definition.alt_text
    assert staged.draft.state == "staged"
    assert staged.artifact.digest == definition.expected_digest
    assert staged.artifact.mime_type == definition.mime_type
    assert staged.artifact.width == definition.width
    assert staged.artifact.height == definition.height
    assert staged.artifact.byte_size == 1_753_013
    assert staged.artifact.byte_size <= ImagePostContract.max_blob_bytes()

    assert staged.artifact.source_metadata["identity"] == "ai_agent_self_portrait"
    assert staged.artifact.source_metadata["subject"] == "agentjido"
    assert staged.artifact.state == "staged"

    refute_received {:upload_blob, _bytes, _mime_type}
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "shows the complete top-level post in the local preview contract" do
    assert {:ok, staged} = SelfPortraitDraft.stage()
    definition = SelfPortraitDraft.definition()

    assert [preview] = Inspection.snapshot(image_limit: 1).image_drafts
    assert preview.draft_key == definition.draft_key
    assert preview.caption == definition.caption
    assert preview.alt_text == definition.alt_text
    assert preview.validation_state == "valid"
    assert preview.publication_state == "staged"
    assert preview.artifact.digest == definition.expected_digest
    assert preview.artifact.upload_state == "staged"
    assert preview.artifact.preview_data_url =~ "data:image/png;base64,"

    assert {:ok, record} =
             ImagePublisher.build_record(staged.draft, blob(staged.artifact.byte_size),
               langs: ["en"],
               created_at: "2026-10-05T22:30:00.000Z"
             )

    assert record["text"] == definition.caption
    assert get_in(record, ["embed", "images", Access.at(0), "alt"]) == definition.alt_text

    assert get_in(record, ["embed", "images", Access.at(0), "aspectRatio"]) == %{
             "width" => 1024,
             "height" => 1024
           }

    assert :ok = ImagePostContract.validate(record)
    assert ImageDrafts.get(definition.draft_key).state == "staged"
    refute_received {:upload_blob, _bytes, _mime_type}
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "staging the fixed draft again reuses the same durable records" do
    assert {:ok, first} = SelfPortraitDraft.stage()
    assert {:ok, second} = SelfPortraitDraft.stage()

    assert second.reused?
    assert second.artifact_reused?
    assert second.draft == first.draft
    assert second.artifact == first.artifact
    assert Repo.aggregate(ImageDraft, :count, :draft_key) == 1
    assert Repo.aggregate(ImageArtifact, :count, :digest) == 1
  end

  defp blob(size) do
    %{
      "$type" => "blob",
      "ref" => %{"$link" => @cid},
      "mimeType" => "image/png",
      "size" => size
    }
  end
end
