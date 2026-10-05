defmodule JidoDelvetown.Test.FakeSession do
  @moduledoc false

  def session do
    {:ok,
     %ProtoRune.Atproto.Session{
       access_jwt: "test-access-token",
       refresh_jwt: "test-refresh-token",
       handle: "bot.test",
       did: "did:plc:bot",
       service_url: "https://pds.test/xrpc"
     }}
  end
end
