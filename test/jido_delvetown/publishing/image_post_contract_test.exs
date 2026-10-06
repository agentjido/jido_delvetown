defmodule JidoDelvetown.ImagePostContractTest do
  use ExUnit.Case, async: true

  alias JidoDelvetown.ImagePostContract

  @fixture_path Path.expand("../../fixtures/delvetown/image_post_record.json", __DIR__)

  test "accepts the fixture from a current public DelveTown image post" do
    assert :ok = ImagePostContract.validate(fixture_record())
  end

  test "accepts the snake-case atom keys returned by the protocol transport" do
    record = %{
      "$type": "town.delve.feed.post",
      embed: %{
        "$type": "town.delve.embed.images",
        images: [
          %{
            image: %{
              "$type": "blob",
              ref: %{"$link" => fixture_cid()},
              mime_type: "image/webp",
              size: 100
            },
            alt: "A small image",
            aspect_ratio: %{width: 2, height: 1}
          }
        ]
      }
    }

    assert :ok = ImagePostContract.validate(record)
  end

  test "allows four images and an omitted aspect ratio" do
    image = fixture_image() |> Map.delete("aspectRatio")
    record = put_in(fixture_record(), ["embed", "images"], List.duplicate(image, 4))

    assert :ok = ImagePostContract.validate(record)
  end

  test "rejects an incorrect post or embed type" do
    assert {:error, :invalid_post_type} =
             fixture_record()
             |> Map.put("$type", "app.bsky.feed.post")
             |> ImagePostContract.validate()

    assert {:error, :invalid_embed_type} =
             fixture_record()
             |> put_in(["embed", "$type"], "app.bsky.embed.images")
             |> ImagePostContract.validate()
  end

  test "rejects more than four images" do
    record =
      put_in(fixture_record(), ["embed", "images"], List.duplicate(fixture_image(), 5))

    assert {:error, :too_many_images} = ImagePostContract.validate(record)
  end

  test "requires the AT Protocol blob shape" do
    assert {:error, {:invalid_image, 0, :invalid_blob_type}} =
             update_fixture_blob(&Map.put(&1, "$type", "image"))
             |> ImagePostContract.validate()

    assert {:error, {:invalid_image, 0, :invalid_blob_ref}} =
             update_fixture_blob(&Map.put(&1, "ref", %{"$link" => "not-a-cid"}))
             |> ImagePostContract.validate()
  end

  test "accepts image MIME types and rejects other media types" do
    assert :ok =
             update_fixture_blob(&Map.put(&1, "mimeType", "image/avif"))
             |> ImagePostContract.validate()

    assert {:error, {:invalid_image, 0, :unsupported_mime_type}} =
             update_fixture_blob(&Map.put(&1, "mimeType", "video/mp4"))
             |> ImagePostContract.validate()
  end

  test "enforces the 2,000,000 byte blob limit" do
    assert :ok =
             update_fixture_blob(&Map.put(&1, "size", ImagePostContract.max_blob_bytes()))
             |> ImagePostContract.validate()

    assert {:error, {:invalid_image, 0, :blob_too_large}} =
             update_fixture_blob(&Map.put(&1, "size", ImagePostContract.max_blob_bytes() + 1))
             |> ImagePostContract.validate()
  end

  test "requires alt text to be a string but permits the remote empty value" do
    assert :ok = ImagePostContract.validate(fixture_record())

    assert {:error, {:invalid_image, 0, :invalid_alt}} =
             fixture_record()
             |> put_in(["embed", "images", Access.at(0), "alt"], nil)
             |> ImagePostContract.validate()
  end

  test "accepts an optional positive-integer aspect ratio" do
    assert {:error, {:invalid_image, 0, :invalid_aspect_ratio}} =
             fixture_record()
             |> put_in(["embed", "images", Access.at(0), "aspectRatio", "width"], 0)
             |> ImagePostContract.validate()
  end

  defp fixture do
    @fixture_path
    |> File.read!()
    |> Jason.decode!()
  end

  defp fixture_record, do: fixture()["record"]
  defp fixture_image, do: get_in(fixture_record(), ["embed", "images", Access.at(0)])
  defp fixture_cid, do: get_in(fixture_image(), ["image", "ref", "$link"])

  defp update_fixture_blob(update) do
    update_in(fixture_record(), ["embed", "images", Access.at(0), "image"], update)
  end
end
