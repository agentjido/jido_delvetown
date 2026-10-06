defmodule JidoDelvetown.ImageDraftsTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.ImageDrafts
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{ImageArtifact, ImageDraft}

  @bytes <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "fixture">>

  setup do
    Repo.delete_all(ImageDraft)
    Repo.delete_all(ImageArtifact)
    :ok
  end

  test "stages durable image bytes and draft metadata" do
    assert {:ok, result} =
             ImageDrafts.stage("self-portrait:one", @bytes, valid_attrs())

    expected_digest = ImageDrafts.digest(@bytes)

    assert result.reused? == false
    assert result.artifact_reused? == false
    assert result.draft.key == "self-portrait:one"
    assert result.draft.artifact_digest == expected_digest
    assert result.draft.caption == "AgentJido joins the image thread."
    assert result.draft.alt_text == "A green robot at a writing desk."
    assert result.draft.state == "staged"
    assert result.draft.failure == nil

    assert result.artifact.digest == expected_digest
    assert result.artifact.bytes == @bytes
    assert result.artifact.mime_type == "image/png"
    assert result.artifact.byte_size == byte_size(@bytes)
    assert result.artifact.width == 640
    assert result.artifact.height == 480
    assert result.artifact.source_metadata == %{"generator" => "fixture", "seed" => 42}
    assert result.artifact.state == "staged"
    assert result.artifact.failure == nil

    assert ImageDrafts.get("self-portrait:one") == result.draft
    assert ImageDrafts.get_artifact(expected_digest) == result.artifact
  end

  test "reuses the durable records for the same logical draft" do
    assert {:ok, first} = ImageDrafts.stage("stable-key", @bytes, valid_attrs())
    assert {:ok, second} = ImageDrafts.stage("stable-key", @bytes, valid_attrs())

    assert second.reused?
    assert second.artifact_reused?
    assert second.draft == first.draft
    assert second.artifact == first.artifact
    assert Repo.aggregate(ImageDraft, :count, :draft_key) == 1
    assert Repo.aggregate(ImageArtifact, :count, :digest) == 1
  end

  test "reuses one content-addressed artifact across logical drafts" do
    assert {:ok, first} = ImageDrafts.stage("draft:one", @bytes, valid_attrs())

    attrs = %{valid_attrs() | caption: "A second use of the same image."}
    assert {:ok, second} = ImageDrafts.stage("draft:two", @bytes, attrs)

    refute second.reused?
    assert second.artifact_reused?
    assert second.artifact.digest == first.artifact.digest
    assert Repo.aggregate(ImageDraft, :count, :draft_key) == 2
    assert Repo.aggregate(ImageArtifact, :count, :digest) == 1
  end

  test "rejects a conflicting retry for one logical draft" do
    assert {:ok, _result} = ImageDrafts.stage("stable-key", @bytes, valid_attrs())

    changed = %{valid_attrs() | caption: "Changed caption"}

    assert {:error, {:draft_conflict, :caption}} =
             ImageDrafts.stage("stable-key", @bytes, changed)

    assert ImageDrafts.get("stable-key").caption == valid_attrs().caption
  end

  test "enriches missing artifact dimensions on a later stage" do
    without_dimensions = %{valid_attrs() | width: nil, height: nil}
    assert {:ok, first} = ImageDrafts.stage("draft:one", @bytes, without_dimensions)
    assert first.artifact.width == nil

    assert {:ok, second} = ImageDrafts.stage("draft:two", @bytes, valid_attrs())
    assert second.artifact_reused?
    assert second.artifact.width == 640
    assert second.artifact.height == 480
  end

  test "rejects unsafe or unbounded inputs before writing" do
    invalid = [
      {"", @bytes, valid_attrs(), :invalid_draft_key},
      {"draft", <<>>, valid_attrs(), :empty_image},
      {"draft", :binary.copy(<<0>>, 2_000_001), valid_attrs(), :image_too_large},
      {"draft", @bytes, %{valid_attrs() | mime_type: "image/svg+xml"}, :unsupported_mime_type},
      {"draft", @bytes, %{valid_attrs() | width: 640, height: nil}, :invalid_dimensions},
      {"draft", @bytes, %{valid_attrs() | width: 16_385}, :invalid_dimensions},
      {"draft", @bytes, %{valid_attrs() | caption: " "}, :invalid_caption},
      {"draft", @bytes, %{valid_attrs() | caption: <<0xFF>>}, :invalid_caption},
      {"draft", @bytes, %{valid_attrs() | caption: String.duplicate("a", 301)},
       :caption_too_long},
      {"draft", @bytes, %{valid_attrs() | alt_text: ""}, :invalid_alt_text},
      {"draft", @bytes, %{valid_attrs() | alt_text: String.duplicate("a", 1_001)},
       :alt_text_too_long}
    ]

    Enum.each(invalid, fn {key, bytes, attrs, reason} ->
      assert {:error, ^reason} = ImageDrafts.stage(key, bytes, attrs)
    end)

    assert Repo.aggregate(ImageDraft, :count, :draft_key) == 0
    assert Repo.aggregate(ImageArtifact, :count, :digest) == 0
  end

  defp valid_attrs do
    %{
      caption: "AgentJido joins the image thread.",
      alt_text: "A green robot at a writing desk.",
      mime_type: "image/png",
      width: 640,
      height: 480,
      source_metadata: %{generator: :fixture, seed: 42}
    }
  end
end
