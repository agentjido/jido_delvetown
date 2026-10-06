defmodule JidoDelvetown.ImagePipelineTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{
    ImageDrafts,
    ImagePublisher,
    ImageStager,
    Inspection,
    InteractionLedger,
    ManualPublisher,
    Repo
  }

  alias JidoDelvetown.Storage.{
    AuditEvent,
    Effect,
    ImageArtifact,
    ImageDraft,
    InteractionEvent
  }

  alias JidoDelvetown.Test.{FakeSession, FakeTransport}

  @bytes <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "pipeline-fixture">>
  @cid "bafkreid2wtyqjcrjwqf7vqumwnnhjq73hlk2h335lxspj6ftcgw7net53a"
  @created_at "2026-10-05T22:00:00.000Z"

  setup do
    clear_tables()

    previous = %{
      session_module: Application.get_env(:jido_delvetown, :session_module),
      transport: Application.get_env(:jido_delvetown, :transport),
      test_owner: Application.get_env(:jido_delvetown, :test_owner),
      upload_blob_result: Application.get_env(:jido_delvetown, :upload_blob_result),
      create_result: Application.get_env(:jido_delvetown, :create_result),
      get_result: Application.get_env(:jido_delvetown, :get_result)
    }

    old_write = System.get_env("DELVETOWN_WRITE_ENABLED")
    old_manual = System.get_env("DELVETOWN_MANUAL_PUBLISH_ENABLED")

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :test_owner, self())
    System.put_env("DELVETOWN_WRITE_ENABLED", "false")
    System.put_env("DELVETOWN_MANUAL_PUBLISH_ENABLED", "true")

    path =
      Path.join(
        System.tmp_dir!(),
        "jido_delvetown_pipeline_#{System.unique_integer([:positive])}.png"
      )

    File.write!(path, @bytes)

    on_exit(fn ->
      clear_tables()
      restore_env(previous)
      restore_system_env("DELVETOWN_WRITE_ENABLED", old_write)
      restore_system_env("DELVETOWN_MANUAL_PUBLISH_ENABLED", old_manual)
      File.rm(path)
    end)

    %{path: path}
  end

  test "stages, previews, publishes, and reuses one image draft", %{path: path} do
    assert {:ok, staged} = ImageStager.stage_file("pipeline:complete", path, valid_attrs())
    assert staged.draft.state == "staged"
    assert staged.artifact.state == "staged"

    assert [preview] = Inspection.snapshot(image_limit: 1).image_drafts
    assert preview.validation_state == "valid"
    assert preview.artifact.upload_state == "staged"
    assert preview.publication_state == "staged"
    assert preview.artifact.preview_data_url == "data:image/png;base64,#{Base.encode64(@bytes)}"
    refute_received {:upload_blob, _bytes, _mime_type}
    refute_received {:create_record, _collection, _record, _rkey}

    configure_upload()

    assert {:ok, published} =
             ImagePublisher.publish_manual("pipeline:complete", created_at: @created_at)

    assert_received {:upload_blob, @bytes, "image/png"}
    assert_received {:create_record, "town.delve.feed.post", record, rkey}
    assert record == published.record
    assert get_in(record, ["embed", "images", Access.at(0), "alt"]) == valid_attrs().alt_text

    assert get_in(record, ["embed", "images", Access.at(0), "aspectRatio"]) == %{
             "width" => 640,
             "height" => 480
           }

    assert ImageDrafts.get("pipeline:complete").state == "published"

    restarted_caller =
      Task.async(fn ->
        ImagePublisher.publish_manual("pipeline:complete", created_at: "2026-10-06T01:00:00Z")
      end)

    assert {:ok, repeated} = Task.await(restarted_caller)
    assert repeated.reused?
    assert repeated.record == published.record
    refute_received {:upload_blob, _bytes, _mime_type}
    refute_received {:create_record, _collection, _record, ^rkey}
  end

  test "a new caller retries the exact durable bytes after an upload timeout" do
    stage_bytes("pipeline:upload-restart")
    Application.put_env(:jido_delvetown, :upload_blob_result, {:error, :timeout})

    first = Task.async(fn -> ImagePublisher.publish_manual("pipeline:upload-restart") end)

    assert {:error, {:blob_upload_failed, {:transport, :timeout}}} = Task.await(first)
    assert_received {:upload_blob, first_bytes, "image/png"}
    assert first_bytes == @bytes
    refute_received {:create_record, _collection, _record, _rkey}

    uncertain = ImageDrafts.get("pipeline:upload-restart")
    assert uncertain.artifact.state == "upload_uncertain"
    assert uncertain.artifact.upload_attempt_count == 1
    assert uncertain.artifact.upload_receipt == nil
    assert uncertain.state == "staged"

    configure_upload()

    restarted_caller =
      Task.async(fn -> ImagePublisher.publish_manual("pipeline:upload-restart") end)

    assert {:ok, published} = Task.await(restarted_caller)
    assert_received {:upload_blob, second_bytes, "image/png"}
    assert second_bytes == first_bytes
    assert_received {:create_record, "town.delve.feed.post", _record, _rkey}
    assert published.draft.artifact.upload_attempt_count == 2
    assert published.draft.state == "published"
  end

  test "a new caller reuses the saved record and record key after a post timeout" do
    stage_bytes("pipeline:post-restart")
    configure_upload()
    Application.put_env(:jido_delvetown, :create_result, {:error, :timeout})
    Application.put_env(:jido_delvetown, :get_result, {:error, :not_found})

    first =
      Task.async(fn ->
        ImagePublisher.publish_manual("pipeline:post-restart", created_at: @created_at)
      end)

    assert {:error, {:create_uncertain, :timeout, first_rkey}} = Task.await(first)
    assert_received {:upload_blob, @bytes, "image/png"}
    assert_received {:create_record, "town.delve.feed.post", first_record, ^first_rkey}
    assert_received {:get_record, "town.delve.feed.post", ^first_rkey}

    uncertain = ImageDrafts.get("pipeline:post-restart")
    assert uncertain.state == "publish_uncertain"
    assert uncertain.post_record == first_record
    assert uncertain.post_receipt == nil

    Application.delete_env(:jido_delvetown, :create_result)

    restarted_caller =
      Task.async(fn ->
        ImagePublisher.publish_manual(
          "pipeline:post-restart",
          created_at: "2026-10-06T01:00:00Z"
        )
      end)

    assert {:ok, published} = Task.await(restarted_caller)
    assert_received {:get_record, "town.delve.feed.post", ^first_rkey}
    assert_received {:create_record, "town.delve.feed.post", second_record, ^first_rkey}
    assert second_record == first_record
    assert published.record == first_record
    refute_received {:upload_blob, _bytes, _mime_type}
  end

  test "review and invalid input paths make no remote writes", %{path: path} do
    System.put_env("DELVETOWN_MANUAL_PUBLISH_ENABLED", "false")

    assert {:ok, _staged} = ImageStager.stage_file("pipeline:review", path, valid_attrs())
    assert [_preview] = Inspection.snapshot(image_limit: 1).image_drafts

    assert {:error, :invalid_alt_text} =
             ImageStager.stage_bytes(
               "pipeline:no-alt",
               @bytes,
               %{valid_attrs() | alt_text: ""} |> Map.put(:mime_type, "image/png")
             )

    assert {:error, :unsupported_mime_type} =
             ImageStager.stage_bytes(
               "pipeline:unsafe",
               "<svg/>",
               valid_attrs() |> Map.put(:mime_type, "image/svg+xml")
             )

    oversized = :binary.copy(<<0>>, 2_000_001)

    assert {:error, :image_too_large} =
             ImageStager.stage_bytes(
               "pipeline:oversized",
               oversized,
               valid_attrs() |> Map.put(:mime_type, "image/png")
             )

    assert {:error, :manual_publish_disabled} =
             ImagePublisher.publish_manual("pipeline:review")

    refute_received {:upload_blob, _bytes, _mime_type}
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "the existing text draft publication path remains unchanged" do
    now = ~U[2026-10-05 22:00:00.000000Z]

    Repo.insert!(%InteractionEvent{
      event_key: "pipeline:text-post",
      kind: "timeline",
      occurred_at: now,
      state: "completed",
      attempt_count: 1,
      payload: %{
        "action" => "post",
        "cycle_status" => "simulated",
        "text" => "A text-only draft stays text-only."
      },
      terminal_at: now
    })

    assert {:ok, publication} = ManualPublisher.publish("pipeline:text-post")
    assert publication.status == "completed"
    assert_received {:create_record, "town.delve.feed.post", record, _rkey}
    assert record.text == "A text-only draft stays text-only."
    refute Map.has_key?(record, :embed)
    refute Map.has_key?(record, "embed")

    assert InteractionLedger.event("pipeline:text-post").payload["manual_publication"]["status"] ==
             "completed"
  end

  defp stage_bytes(key) do
    assert {:ok, _result} =
             ImageStager.stage_bytes(
               key,
               @bytes,
               valid_attrs() |> Map.put(:mime_type, "image/png")
             )
  end

  defp valid_attrs do
    %{
      caption: "AgentJido verifies the image boundary.",
      alt_text: "A green robot checks a durable image pipeline.",
      width: 640,
      height: 480,
      source_metadata: %{source: "pipeline_test"}
    }
  end

  defp configure_upload do
    Application.put_env(:jido_delvetown, :upload_blob_result, {
      :ok,
      %{
        blob: %{
          "$type" => "blob",
          ref: %{"$link" => @cid},
          mime_type: "image/png",
          size: byte_size(@bytes)
        }
      }
    })
  end

  defp clear_tables do
    Enum.each(
      [ImageDraft, ImageArtifact, AuditEvent, Effect, InteractionEvent],
      &Repo.delete_all/1
    )
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
