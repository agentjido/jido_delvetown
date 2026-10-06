defmodule JidoDelvetown.WelcomePostTest do
  use ExUnit.Case, async: true

  alias JidoDelvetown.WelcomePost

  @fixture_path Path.expand("../fixtures/delvetown/mention_post_record.json", __DIR__)
  @did "did:plc:newmember"
  @handle "new.delve.town"

  test "builds a top-level DelveTown post with one mention facet" do
    text = "@new.delve.town Welcome to DelveTown."

    assert {:ok, record} = WelcomePost.record(text, @did, @handle)
    assert record.text == text
    assert record.langs == ["en"]
    assert is_binary(record.created_at)
    refute Map.has_key?(record, :reply)

    assert [facet] = record.facets
    assert facet["$type"] == "town.delve.richtext.facet"
    assert facet.index == %{byte_start: 0, byte_end: 15}

    assert facet.features == [
             %{"$type" => "town.delve.richtext.facet#mention", did: @did}
           ]
  end

  test "uses UTF-8 byte indexes, not grapheme indexes" do
    text = "👋 Welcome @new.delve.town"

    assert {:ok, facet} = WelcomePost.mention_facet(text, @handle, @did)
    assert facet.index == %{byte_start: 13, byte_end: 28}
    assert binary_part(text, 13, 15) == "@new.delve.town"
  end

  test "builds a reply only for a safe top-level actor post" do
    uri = "at://#{@did}/town.delve.feed.post/3mx6intro"
    target = %{uri: uri, cid: "bafyreintro", root: %{uri: uri, cid: "bafyreintro"}}

    assert {:ok, record} =
             WelcomePost.record("@new.delve.town Welcome.", @did, @handle, target)

    assert record.reply == %{
             parent: %{uri: uri, cid: "bafyreintro"},
             root: %{uri: uri, cid: "bafyreintro"}
           }

    unsafe = put_in(target, [:root, :uri], "at://did:plc:other/town.delve.feed.post/root")

    assert {:error, :invalid_welcome_record} =
             WelcomePost.record("@new.delve.town Welcome.", @did, @handle, unsafe)
  end

  test "rejects unsafe identities and text without the resolved mention" do
    refute WelcomePost.valid_identity?("did:plc:newmember", "not a handle")
    refute WelcomePost.valid_identity?("unsafe did", @handle)

    assert {:error, :missing_welcome_mention} =
             WelcomePost.mention_facet("Welcome.", @handle, @did)
  end

  test "matches the mention record shape observed on the live DelveTown protocol" do
    fixture = @fixture_path |> File.read!() |> Jason.decode!()
    expected = fixture["record"]

    assert WelcomePost.facet_type() == get_in(expected, ["facets", Access.at(0), "$type"])

    assert WelcomePost.mention_type() ==
             get_in(expected, ["facets", Access.at(0), "features", Access.at(0), "$type"])

    assert {:ok, record} = WelcomePost.record(expected["text"], @did, @handle)

    wire_record =
      record
      |> Map.put("$type", "town.delve.feed.post")
      |> ProtoRune.Case.camelize_enum()
      |> Jason.encode!()
      |> Jason.decode!()

    assert wire_record["$type"] == expected["$type"]
    assert wire_record["facets"] == expected["facets"]
  end
end
