defmodule JidoDelvetown.ImageUploaderTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias JidoDelvetown.ImageDrafts
  alias JidoDelvetown.ImageUploader
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{ImageArtifact, ImageDraft}
  alias JidoDelvetown.Test.{FakeSession, FakeTransport}

  @bytes <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "upload-fixture">>
  @cid "bafkreid2wtyqjcrjwqf7vqumwnnhjq73hlk2h335lxspj6ftcgw7net53a"

  setup do
    Repo.delete_all(ImageDraft)
    Repo.delete_all(ImageArtifact)

    previous = %{
      session_module: Application.get_env(:jido_delvetown, :session_module),
      transport: Application.get_env(:jido_delvetown, :transport),
      test_owner: Application.get_env(:jido_delvetown, :test_owner),
      upload_blob_result: Application.get_env(:jido_delvetown, :upload_blob_result)
    }

    old_write = System.get_env("DELVETOWN_WRITE_ENABLED")

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :test_owner, self())

    on_exit(fn ->
      restore_env(previous)
      restore_system_env("DELVETOWN_WRITE_ENABLED", old_write)
    end)

    :ok
  end

  test "uploads a validated staged artifact and saves its receipt" do
    System.put_env("DELVETOWN_WRITE_ENABLED", "true")
    digest = stage_artifact()
    Application.put_env(:jido_delvetown, :upload_blob_result, {:ok, %{blob: blob()}})

    assert {:ok, result} = ImageUploader.upload(digest)
    refute result.reused?
    assert result.blob == string_key_blob()
    assert result.artifact.state == "uploaded"
    assert result.artifact.upload_attempt_count == 1
    assert result.artifact.uploaded_at
    assert_received {:upload_blob, @bytes, "image/png"}

    assert ImageDrafts.get_artifact(digest).upload_receipt == string_key_blob()

    assert {:ok, reused} = ImageUploader.upload(digest)
    assert reused.reused?
    assert reused.blob == string_key_blob()
    refute_received {:upload_blob, _bytes, _mime_type}
  end

  test "retries the exact bytes after a timeout and a new caller starts" do
    System.put_env("DELVETOWN_WRITE_ENABLED", "true")
    digest = stage_artifact()
    Application.put_env(:jido_delvetown, :upload_blob_result, {:error, :timeout})

    first = Task.async(fn -> ImageUploader.upload(digest) end)
    assert {:error, {:blob_upload_failed, {:transport, :timeout}}} = Task.await(first)
    assert_received {:upload_blob, first_bytes, "image/png"}
    assert first_bytes == @bytes

    uncertain = ImageDrafts.get_artifact(digest)
    assert uncertain.state == "upload_uncertain"
    assert uncertain.upload_attempt_count == 1
    assert uncertain.upload_receipt == nil

    assert uncertain.failure == %{
             "operation" => "upload_blob",
             "reason" => ["transport", "timeout"]
           }

    Application.put_env(:jido_delvetown, :upload_blob_result, {:ok, %{"blob" => blob()}})

    second = Task.async(fn -> ImageUploader.upload(digest) end)
    assert {:ok, %{reused?: false}} = Task.await(second)
    assert_received {:upload_blob, second_bytes, "image/png"}
    assert second_bytes == first_bytes

    uploaded = ImageDrafts.get_artifact(digest)
    assert uploaded.state == "uploaded"
    assert uploaded.upload_attempt_count == 2
    assert uploaded.upload_receipt == string_key_blob()
    assert uploaded.failure == nil
  end

  test "rejects invalid stored MIME data before an upload attempt" do
    System.put_env("DELVETOWN_WRITE_ENABLED", "true")
    digest = stage_artifact()

    from(artifact in ImageArtifact, where: artifact.digest == ^digest)
    |> Repo.update_all(set: [mime_type: "image/svg+xml"])

    assert {:error, :unsupported_mime_type} = ImageUploader.upload(digest)
    assert ImageDrafts.get_artifact(digest).upload_attempt_count == 0
    refute_received {:upload_blob, _bytes, _mime_type}
  end

  test "does not reserve or send an upload when writes are disabled" do
    System.put_env("DELVETOWN_WRITE_ENABLED", "false")
    digest = stage_artifact()

    assert {:error, :writes_disabled} = ImageUploader.upload(digest)

    artifact = ImageDrafts.get_artifact(digest)
    assert artifact.state == "staged"
    assert artifact.upload_attempt_count == 0
    refute_received {:upload_blob, _bytes, _mime_type}
  end

  test "does not complete an upload without a valid durable receipt" do
    System.put_env("DELVETOWN_WRITE_ENABLED", "true")
    digest = stage_artifact()
    Application.put_env(:jido_delvetown, :upload_blob_result, {:ok, %{blob: %{}}})

    assert {:error, {:blob_upload_failed, {:invalid_upload_receipt, :invalid_blob_type}}} =
             ImageUploader.upload(digest)

    artifact = ImageDrafts.get_artifact(digest)
    assert artifact.state == "upload_uncertain"
    assert artifact.upload_receipt == nil
    assert artifact.uploaded_at == nil
  end

  defp stage_artifact do
    assert {:ok, result} =
             ImageDrafts.stage("upload:test", @bytes, %{
               caption: "Upload contract test.",
               alt_text: "A small image fixture.",
               mime_type: "image/png",
               width: 16,
               height: 16
             })

    result.artifact.digest
  end

  defp blob do
    %{
      "$type" => "blob",
      ref: %{"$link" => @cid},
      mime_type: "image/png",
      size: byte_size(@bytes)
    }
  end

  defp string_key_blob do
    %{
      "$type" => "blob",
      "ref" => %{"$link" => @cid},
      "mimeType" => "image/png",
      "size" => byte_size(@bytes)
    }
  end

  defp restore_env(values) do
    Enum.each(values, fn
      {key, nil} -> Application.delete_env(:jido_delvetown, key)
      {key, value} -> Application.put_env(:jido_delvetown, key, value)
    end)
  end

  defp restore_system_env(name, nil), do: System.delete_env(name)
  defp restore_system_env(name, value), do: System.put_env(name, value)
end
