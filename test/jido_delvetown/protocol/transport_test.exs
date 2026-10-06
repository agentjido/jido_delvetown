defmodule JidoDelvetown.TransportTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Test.HTTPAdapter
  alias JidoDelvetown.Transport.ProtoRune, as: Transport

  setup do
    old_owner = Application.get_env(:jido_delvetown, :test_owner)
    Application.put_env(:jido_delvetown, :test_owner, self())

    on_exit(fn ->
      if old_owner,
        do: Application.put_env(:jido_delvetown, :test_owner, old_owner),
        else: Application.delete_env(:jido_delvetown, :test_owner)
    end)
  end

  test "AppView queries use the proxy header and repeated array parameters" do
    session = %ProtoRune.Atproto.Session{
      access_jwt: "access-token",
      refresh_jwt: "refresh-token",
      handle: "bot.test",
      did: "did:plc:bot",
      service_url: "https://pds.test/xrpc"
    }

    assert {:ok, %{}} =
             Transport.appview_query(
               session,
               "town.delve.feed.getPosts",
               %{parent_height: 4, uris: ["at://one", "at://two"]},
               http: [adapter: HTTPAdapter, rate_limit: false, retry: false]
             )

    assert_received {:http_request, :get, url, opts}
    assert url =~ "/xrpc/town.delve.feed.getPosts?"
    assert url =~ "parentHeight=4"
    assert length(Regex.scan(~r/(?:\?|&)uris=/, url)) == 2

    headers = Keyword.fetch!(opts, :headers) |> Map.new()
    assert headers["atproto-proxy"] == "did:web:api.delve.town#bsky_appview"
    assert headers["authorization"] == "Bearer access-token"
  end

  test "blob uploads send exact bytes with authentication and content type" do
    session = %ProtoRune.Atproto.Session{
      access_jwt: "access-token",
      refresh_jwt: "refresh-token",
      handle: "bot.test",
      did: "did:plc:bot",
      service_url: "https://pds.test/xrpc"
    }

    bytes = <<0, 1, 2, 3, 255>>

    assert {:ok, %{}} =
             Transport.upload_blob(session, bytes, "image/png",
               http: [adapter: HTTPAdapter, rate_limit: false, retry: false]
             )

    assert_received {:http_request, :post, url, opts}
    assert url == "https://pds.test/xrpc/com.atproto.repo.uploadBlob"
    assert Keyword.fetch!(opts, :body) == bytes

    headers = Keyword.fetch!(opts, :headers) |> Map.new()
    assert headers["content-type"] == "image/png"
    assert headers["authorization"] == "Bearer access-token"
  end
end
