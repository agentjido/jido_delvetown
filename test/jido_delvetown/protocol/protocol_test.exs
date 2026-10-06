defmodule JidoDelvetown.ProtocolTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.Actions.{CreatePost, LikePost}
  alias JidoDelvetown.AuditLog
  alias JidoDelvetown.EffectStore
  alias JidoDelvetown.Protocol
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{AuditEvent, Effect}
  alias JidoDelvetown.Test.{FakeSession, FakeTransport, RuntimeSettings}

  setup do
    Repo.delete_all(AuditEvent)
    Repo.delete_all(Effect)

    previous = %{
      session_module: Application.get_env(:jido_delvetown, :session_module),
      transport: Application.get_env(:jido_delvetown, :transport),
      effect_store: Application.get_env(:jido_delvetown, :effect_store),
      effect_store_opts: Application.get_env(:jido_delvetown, :effect_store_opts),
      test_owner: Application.get_env(:jido_delvetown, :test_owner),
      create_result: Application.get_env(:jido_delvetown, :create_result),
      get_result: Application.get_env(:jido_delvetown, :get_result),
      delete_result: Application.get_env(:jido_delvetown, :delete_result)
    }

    Application.put_env(:jido_delvetown, :session_module, FakeSession)
    Application.put_env(:jido_delvetown, :transport, FakeTransport)
    Application.put_env(:jido_delvetown, :effect_store, EffectStore)
    Application.put_env(:jido_delvetown, :effect_store_opts, repo: Repo)
    Application.put_env(:jido_delvetown, :test_owner, self())
    restore_settings = RuntimeSettings.preserve!(autonomy_mode: "observe")

    on_exit(fn ->
      restore_env(previous)
      restore_settings.()
    end)

    :ok
  end

  test "write Actions are disabled by default" do
    RuntimeSettings.update!(autonomy_mode: "observe")

    assert {:error, :writes_disabled} =
             LikePost.run(%{uri: "at://did:plc:other/town.delve.feed.post/one", cid: "cid"}, %{})

    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "a completed effect reuses its saved receipt" do
    RuntimeSettings.update!(autonomy_mode: "autonomous")
    params = %{uri: "at://did:plc:other/town.delve.feed.post/one", cid: "cid"}

    assert {:ok, %{reused?: false}} = LikePost.run(params, %{})
    assert_received {:create_record, "town.delve.feed.like", record, rkey}
    assert record["$type"] == "town.delve.feed.like"
    assert is_binary(rkey)

    assert [%{type: :create_record, data: %{record_uri: record_uri}} | _events] =
             AuditLog.recent(1)

    assert record_uri == "at://did:plc:bot/town.delve.feed.like/#{rkey}"

    assert {:ok, %{reused?: true}} = LikePost.run(params, %{})
    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "an uncertain create is reconciled with the fixed record key" do
    RuntimeSettings.update!(autonomy_mode: "autonomous")
    Application.put_env(:jido_delvetown, :create_result, {:error, :timeout})

    Application.put_env(
      :jido_delvetown,
      :get_result,
      {:ok, %{uri: "at://reconciled", cid: "cid"}}
    )

    assert {:ok, %{reconciled?: true}} =
             Protocol.create_record("effect-key", "town.delve.feed.like", %{subject: %{}})

    assert_received {:create_record, "town.delve.feed.like", _record, rkey}
    assert_received {:get_record, "town.delve.feed.like", ^rkey}
    assert %{status: :completed, rkey: ^rkey} = EffectStore.get("effect-key")
  end

  test "a lost reply retries with the same record key" do
    RuntimeSettings.update!(autonomy_mode: "autonomous")
    Application.put_env(:jido_delvetown, :create_result, {:error, :timeout})
    Application.put_env(:jido_delvetown, :get_result, {:error, :not_found})

    key = Protocol.effect_key("reply", ["at://did:plc:other/town.delve.feed.post/parent"])
    record = %{text: "A reply", reply: %{}}

    assert {:error, {:create_uncertain, :timeout, first_rkey}} =
             Protocol.create_record(key, "town.delve.feed.post", record)

    assert_received {:create_record, "town.delve.feed.post", _record, ^first_rkey}
    assert_received {:get_record, "town.delve.feed.post", ^first_rkey}
    assert %{status: :uncertain, attempt_count: 1} = EffectStore.get(key)

    Application.delete_env(:jido_delvetown, :create_result)

    assert {:ok, %{reconciled?: false, reused?: false}} =
             Protocol.create_record(key, "town.delve.feed.post", record)

    assert_received {:get_record, "town.delve.feed.post", ^first_rkey}
    assert_received {:create_record, "town.delve.feed.post", _record, ^first_rkey}

    assert %{status: :completed, attempt_count: 2, rkey: ^first_rkey} =
             EffectStore.get(key)
  end

  test "an uncertain effect reconciles remote success before another write" do
    RuntimeSettings.update!(autonomy_mode: "autonomous")
    key = "reply:remote-success"

    assert {:ok, reserved} = EffectStore.reserve(key, "town.delve.feed.post")

    assert {:ok, %{status: :uncertain}} = EffectStore.begin_attempt(key)

    Application.put_env(
      :jido_delvetown,
      :get_result,
      {:ok, %{uri: "at://remote/reply", cid: "remote-cid"}}
    )

    assert {:ok, %{reconciled?: true, reused?: false}} =
             Protocol.create_record(key, "town.delve.feed.post", %{text: "Already written"})

    assert_received {:get_record, "town.delve.feed.post", rkey}
    assert rkey == reserved.rkey
    refute_received {:create_record, _collection, _record, _rkey}

    assert %{status: :completed, attempt_count: 1, rkey: ^rkey} =
             EffectStore.get(key)
  end

  test "an original post uses its stable opportunity identifier" do
    RuntimeSettings.update!(autonomy_mode: "autonomous")

    assert {:ok, %{reused?: false}} =
             CreatePost.run(
               %{opportunity_id: "daily:2026-10-05", text: "First draft", langs: ["en"]},
               %{}
             )

    assert_received {:create_record, "town.delve.feed.post", _record, rkey}

    assert {:ok, %{reused?: true}} =
             CreatePost.run(
               %{opportunity_id: "daily:2026-10-05", text: "Changed draft", langs: ["en"]},
               %{}
             )

    refute_received {:create_record, _collection, _record, _rkey}

    key = Protocol.effect_key("post", ["daily:2026-10-05"])

    assert %{status: :completed, rkey: ^rkey, subject_key: "daily:2026-10-05"} =
             EffectStore.get(key)
  end

  test "an owned deletion is durable and idempotent" do
    RuntimeSettings.update!(autonomy_mode: "autonomous")
    uri = "at://did:plc:bot/town.delve.feed.post/owned-record"

    assert {:ok, %{deleted?: true, reused?: false}} = Protocol.delete_own_record(uri)
    assert_received {:delete_record, "town.delve.feed.post", "owned-record"}

    assert {:ok, %{deleted?: true, reused?: true}} = Protocol.delete_own_record(uri)
    refute_received {:delete_record, _collection, _rkey}

    key = Protocol.effect_key("delete", [uri])

    assert %{status: :completed, rkey: "owned-record", subject_key: ^uri} =
             EffectStore.get(key)
  end

  test "a permanent create failure is not retried" do
    RuntimeSettings.update!(autonomy_mode: "autonomous")

    Application.put_env(
      :jido_delvetown,
      :create_result,
      {:error, %ProtoRune.XRPC.Error{reason: :forbidden, http_status: 403}}
    )

    key = "like:permanent"

    assert {:error, {:create_failed_permanently, %{http_status: 403}}} =
             Protocol.create_record(key, "town.delve.feed.like", %{subject: %{}})

    assert_received {:create_record, "town.delve.feed.like", _record, _rkey}
    assert %{status: :permanent_failure, attempt_count: 1} = EffectStore.get(key)

    assert {:error, {:effect_failed_permanently, _failure}} =
             Protocol.create_record(key, "town.delve.feed.like", %{subject: %{}})

    refute_received {:create_record, _collection, _record, _rkey}
  end

  test "delete rejects a record owned by another account" do
    RuntimeSettings.update!(autonomy_mode: "autonomous")

    assert {:error, :record_not_owned} =
             Protocol.delete_own_record("at://did:plc:other/town.delve.feed.like/record-key")

    refute_received {:delete_record, _collection, _rkey}
  end

  defp restore_env(values) do
    Enum.each(values, fn
      {key, nil} -> Application.delete_env(:jido_delvetown, key)
      {key, value} -> Application.put_env(:jido_delvetown, key, value)
    end)
  end
end
