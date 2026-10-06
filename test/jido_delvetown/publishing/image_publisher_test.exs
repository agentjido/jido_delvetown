defmodule JidoDelvetown.ImagePublisherTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.ImageDrafts
  alias JidoDelvetown.ImagePostContract
  alias JidoDelvetown.ImagePublisher
  alias JidoDelvetown.Protocol
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Settings
  alias JidoDelvetown.Storage.{AuditEvent, Effect, ImageArtifact, ImageDraft}
  alias JidoDelvetown.Test.{FakeSession, FakeTransport, RuntimeSettings}

  @bytes <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, "publish-fixture">>
  @cid "bafkreid2wtyqjcrjwqf7vqumwnnhjq73hlk2h335lxspj6ftcgw7net53a"
  @created_at "2026-10-05T20:08:23.948Z"

  setup do
    Repo.delete_all(ImageDraft)
    Repo.delete_all(ImageArtifact)
    Repo.delete_all(AuditEvent)
    Repo.delete_all(Effect)

    previous = %{
      session_module: Application.get_env(:jido_delvetown, :session_module),
      transport: Application.get_env(:jido_delvetown, :transport),
      test_owner: Application.get_env(:jido_delvetown, :test_owner),
      upload_blob_result: Application.get_env(:jido_delvetown, :upload_blob_result),
      create_result: Application.get_env(:jido_delvetown, :create_result),
      get_result: Application.get_env(:jido_delvetown, :get_result)
    }

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :test_owner, self())

    restore_settings =
      RuntimeSettings.preserve!(
        autonomy_mode: "autonomous",
        manual_publish_enabled: false,
        enabled_actions: ~w(reply like repost post follow welcome)
      )

    on_exit(fn ->
      restore_env(previous)
      restore_settings.()
    end)

    :ok
  end

  test "uploads and publishes a staged image draft as one verified top-level post" do
    stage_draft("image:one", 640, 480)
    configure_upload()

    assert {:ok, result} =
             ImagePublisher.publish("image:one", langs: ["en", "es"], created_at: @created_at)

    assert {:ok, settings} = Settings.reference(result.draft.publication_settings)

    refute result.reused?
    refute result.reconciled?
    assert result.receipt["uri"]
    assert :ok = ImagePostContract.validate(result.record)

    assert result.record == %{
             "$type" => "town.delve.feed.post",
             "text" => "AgentJido shares an image.",
             "langs" => ["en", "es"],
             "createdAt" => @created_at,
             "embed" => %{
               "$type" => "town.delve.embed.images",
               "images" => [
                 %{
                   "image" => wire_blob(),
                   "alt" => "A green robot drawing at a desk.",
                   "aspectRatio" => %{"width" => 640, "height" => 480}
                 }
               ]
             }
           }

    assert_received {:upload_blob, @bytes, "image/png"}
    assert_received {:create_record, "town.delve.feed.post", record, rkey}
    assert record == result.record

    effect_key = Protocol.effect_key("image_post", ["image:one"])

    assert %Effect{
             status: "completed",
             rkey: ^rkey,
             subject_key: "image:one",
             settings: effect_settings
           } = Repo.get(Effect, effect_key)

    assert {:ok, ^settings} = Settings.reference(effect_settings)

    draft = ImageDrafts.get("image:one")
    assert draft.state == "published"
    assert draft.post_effect_key == effect_key
    assert draft.post_record == result.record
    assert draft.post_receipt == result.receipt
    assert {:ok, ^settings} = Settings.reference(draft.publication_settings)
    assert draft.published_at
    assert draft.artifact.state == "uploaded"
    assert draft.artifact.upload_receipt == wire_blob()
  end

  test "a repeated publication reuses its saved post and makes no second write" do
    stage_draft("image:repeat", 640, 480)
    configure_upload()

    assert {:ok, first} =
             ImagePublisher.publish("image:repeat", created_at: @created_at)

    assert_received {:upload_blob, @bytes, "image/png"}
    assert_received {:create_record, "town.delve.feed.post", _record, _rkey}

    assert {:ok, second} =
             ImagePublisher.publish("image:repeat",
               langs: ["fr"],
               created_at: "2026-10-06T01:00:00Z"
             )

    assert second.reused?
    assert second.record == first.record
    assert second.receipt == first.receipt
    refute_received {:upload_blob, _bytes, _mime_type}
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "a timeout retry uses the saved record body and stable record key" do
    stage_draft("image:timeout", 640, 480)
    configure_upload()
    Application.put_env(:jido_delvetown, :create_result, {:error, :timeout})
    Application.put_env(:jido_delvetown, :get_result, {:error, :not_found})

    assert {:error, {:create_uncertain, :timeout, first_rkey}} =
             ImagePublisher.publish("image:timeout", created_at: @created_at)

    assert_received {:upload_blob, @bytes, "image/png"}
    assert_received {:create_record, "town.delve.feed.post", first_record, ^first_rkey}
    assert_received {:get_record, "town.delve.feed.post", ^first_rkey}

    uncertain = ImageDrafts.get("image:timeout")
    assert uncertain.state == "publish_uncertain"
    assert uncertain.post_record == first_record
    assert uncertain.post_receipt == nil
    assert uncertain.failure

    Application.delete_env(:jido_delvetown, :create_result)

    assert {:ok, retried} =
             ImagePublisher.publish("image:timeout",
               langs: ["de"],
               created_at: "2026-10-06T01:00:00Z"
             )

    assert_received {:get_record, "town.delve.feed.post", ^first_rkey}
    assert_received {:create_record, "town.delve.feed.post", second_record, ^first_rkey}
    assert second_record == first_record
    assert retried.record == first_record
    refute_received {:upload_blob, _bytes, _mime_type}

    published = ImageDrafts.get("image:timeout")
    assert published.state == "published"
    assert published.post_receipt
    assert published.failure == nil
  end

  test "omits aspect ratio when the staged artifact has no dimensions" do
    stage_draft("image:no-dimensions", nil, nil)
    configure_upload()

    assert {:ok, result} =
             ImagePublisher.publish("image:no-dimensions", created_at: @created_at)

    image = get_in(result.record, ["embed", "images", Access.at(0)])
    refute Map.has_key?(image, "aspectRatio")
    assert :ok = ImagePostContract.validate(result.record)
  end

  test "rejects invalid publication options before an upload or post write" do
    stage_draft("image:invalid", 640, 480)
    configure_upload()

    assert {:error, :invalid_languages} =
             ImagePublisher.publish("image:invalid", langs: ["en", "es", "fr", "de"])

    assert {:error, :invalid_created_at} =
             ImagePublisher.publish("image:invalid", created_at: "not-a-time")

    refute_received {:upload_blob, _bytes, _mime_type}
    refute_received {:create_record, _collection, _record, _rkey}
    assert ImageDrafts.get("image:invalid").state == "staged"
  end

  test "manual publication uploads and posts while scheduled writes stay off" do
    RuntimeSettings.update!(autonomy_mode: "observe", manual_publish_enabled: true)
    stage_draft("image:manual", 640, 480)
    configure_upload()

    assert {:ok, result} =
             ImagePublisher.publish_manual("image:manual", created_at: @created_at)

    assert result.draft.state == "published"
    assert_received {:upload_blob, @bytes, "image/png"}
    assert_received {:create_record, "town.delve.feed.post", record, _rkey}
    assert record == result.record
  end

  test "manual publication makes no remote call when its permission is off" do
    RuntimeSettings.update!(autonomy_mode: "observe", manual_publish_enabled: false)
    stage_draft("image:manual-disabled", 640, 480)
    configure_upload()

    assert {:error, :manual_publish_disabled} =
             ImagePublisher.publish_manual("image:manual-disabled", created_at: @created_at)

    assert ImageDrafts.get("image:manual-disabled").artifact.state == "staged"
    refute_received {:upload_blob, _bytes, _mime_type}
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "publication makes no remote call when post actions are disabled" do
    RuntimeSettings.update!(enabled_actions: ["like"])
    stage_draft("image:post-disabled", 640, 480)
    configure_upload()

    assert {:error, :action_disabled} =
             ImagePublisher.publish("image:post-disabled", created_at: @created_at)

    refute_received {:upload_blob, _bytes, _mime_type}
    refute_received {:create_record, _collection, _record, _rkey}
  end

  defp stage_draft(key, width, height) do
    assert {:ok, _result} =
             ImageDrafts.stage(key, @bytes, %{
               caption: "AgentJido shares an image.",
               alt_text: "A green robot drawing at a desk.",
               mime_type: "image/png",
               width: width,
               height: height
             })
  end

  defp configure_upload do
    Application.put_env(:jido_delvetown, :upload_blob_result, {:ok, %{blob: blob()}})
  end

  defp blob do
    %{
      "$type" => "blob",
      ref: %{"$link" => @cid},
      mime_type: "image/png",
      size: byte_size(@bytes)
    }
  end

  defp wire_blob do
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
end
