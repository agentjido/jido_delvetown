defmodule JidoDelvetown.ImageStagerTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{ImageStager, Repo}
  alias JidoDelvetown.Storage.{ImageArtifact, ImageDraft}

  @bytes <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "stage-file-fixture">>

  setup do
    Repo.delete_all(ImageDraft)
    Repo.delete_all(ImageArtifact)

    path =
      Path.join(
        System.tmp_dir!(),
        "jido_delvetown_image_#{System.unique_integer([:positive])}.png"
      )

    File.write!(path, @bytes)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "stages a local image without a protocol effect", %{path: path} do
    assert {:ok, result} =
             ImageStager.stage_file("operator:image", path, %{
               caption: "A local image draft.",
               alt_text: "A small PNG test fixture.",
               width: 32,
               height: 24,
               source_metadata: %{workflow: "operator_test"}
             })

    assert result.draft.state == "staged"
    assert result.artifact.state == "staged"
    assert result.artifact.mime_type == "image/png"
    assert result.artifact.bytes == @bytes

    assert result.artifact.source_metadata == %{
             "filename" => Path.basename(path),
             "source" => "local_file",
             "workflow" => "operator_test"
           }

    refute_received {:upload_blob, _bytes, _mime_type}
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "uses the same byte staging interface for a generated image" do
    assert {:ok, result} =
             ImageStager.stage_bytes("generated:image", @bytes, %{
               caption: "A generated image draft.",
               alt_text: "A generated green robot.",
               mime_type: "image/png",
               width: nil,
               height: nil,
               source_metadata: %{source: "req_llm"}
             })

    assert result.draft.key == "generated:image"
    assert result.artifact.source_metadata == %{"source" => "req_llm"}
  end

  test "rejects unavailable files and unsupported extensions", %{path: path} do
    assert {:error, {:image_file_unavailable, :enoent}} =
             ImageStager.stage_file("missing", path <> ".missing", valid_attrs())

    unsupported = Path.rootname(path) <> ".svg"
    File.rename!(path, unsupported)
    on_exit(fn -> File.rm(unsupported) end)

    assert {:error, :unsupported_mime_type} =
             ImageStager.stage_file("unsupported", unsupported, valid_attrs())
  end

  defp valid_attrs do
    %{
      caption: "A local image draft.",
      alt_text: "A small image fixture.",
      width: nil,
      height: nil
    }
  end
end
