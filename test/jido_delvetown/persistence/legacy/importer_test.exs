defmodule JidoDelvetown.Persistence.Legacy.ImporterTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias JidoDelvetown.Persistence.Legacy.Importer
  alias JidoDelvetown.Persistence.Legacy.Startup
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Agent
  alias JidoDelvetown.Storage.{AuditEvent, Effect, InteractionEvent, LegacyImport, ScanState}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "jido_delvetown_import_#{System.unique_integer([:positive])}"
      )

    dets_path = Path.join(root, "legacy.dets")
    checkpoint_path = Path.join(root, "checkpoints")
    File.mkdir_p!(root)

    opts = [
      dets_path: dets_path,
      checkpoint_path: checkpoint_path,
      namespace: "test/import/#{System.unique_integer([:positive])}",
      agent_id: "agent"
    ]

    on_exit(fn -> File.rm_rf(root) end)
    {:ok, opts: opts, dets_path: dets_path, checkpoint_path: checkpoint_path}
  end

  test "imports DETS records and exact checkpoint bytes once", context do
    write_dets(context.dets_path)
    {checkpoint_key, checkpoint_bytes} = write_checkpoint(context.opts)

    Repo.transaction(fn ->
      assert {:ok,
              %{
                cursors: 1,
                seen: 1,
                effects: 1,
                events: 1,
                checkpoints: 1,
                checkpoint_key: ^checkpoint_key
              }} = Importer.preview(context.opts)

      assert {:ok, {:imported, details}} = Importer.run(context.opts)
      assert details["effects"] == 1
      assert details["checkpoints"] == 1

      assert %ScanState{cursor: "cursor-1"} = Repo.get(ScanState, "notifications")

      assert %Effect{status: "completed", rkey: "fixed-rkey", receipt: receipt} =
               Repo.get(Effect, "like:stable")

      assert receipt["uri"] == "at://receipt"
      assert Repo.one(from(event in InteractionEvent, select: count())) >= 1
      assert Repo.one(from(event in AuditEvent, select: count())) >= 1

      assert {:ok, ^checkpoint_bytes} =
               Jido.Persistence.Ecto.get(checkpoint_key, repo: Repo)

      assert {:ok, restored} =
               Jido.Persistence.load_agent(
                 {Jido.Persistence.Ecto, repo: Repo},
                 Agent,
                 "agent",
                 namespace: Keyword.fetch!(context.opts, :namespace)
               )

      assert restored.state.last_run == %{summary: "imported"}

      assert {:ok, {:reused, ^details}} = Importer.run(context.opts)
      assert {:ok, %{status: :verified}} = Importer.verify(context.opts)

      assert Repo.one(
               from(event in AuditEvent,
                 where: like(event.source_key, "legacy:dets:event:%"),
                 select: count()
               )
             ) == 1

      add_audit_event(context.dets_path, 8)

      assert {:ok, {:imported, changed_details}} = Importer.run(context.opts)
      assert changed_details["events"] == 2
      assert {:ok, {:reused, ^changed_details}} = Importer.run(context.opts)

      assert Repo.one(
               from(event in AuditEvent,
                 where: like(event.source_key, "legacy:dets:event:%"),
                 select: count()
               )
             ) == 2

      Repo.rollback(:test_complete)
    end)

    assert is_nil(Repo.get(Effect, "like:stable"))
  end

  test "reports a corrupt DETS source without writing import state", context do
    File.write!(context.dets_path, "not a dets table")

    assert {:error, {:legacy_dets_open_failed, _reason}} =
             Importer.run(context.opts)
  end

  test "reads an unclean DETS file from a repair copy without changing the source", context do
    elixir = System.find_executable("elixir")

    script = """
    path = System.fetch_env!("DELVETOWN_TEST_DETS_PATH")
    {:ok, :unclean_legacy_dets} =
      :dets.open_file(:unclean_legacy_dets, file: String.to_charlist(path), type: :set)
    :ok = :dets.insert(:unclean_legacy_dets, {:cursor, "unclean-cursor"})
    :ok = :dets.sync(:unclean_legacy_dets)
    :erlang.halt(0)
    """

    assert {_output, 0} =
             System.cmd(elixir, ["-e", script],
               env: [{"DELVETOWN_TEST_DETS_PATH", context.dets_path}]
             )

    source_bytes = File.read!(context.dets_path)

    assert {:ok, %{cursors: 1}} = Importer.preview(context.opts)
    assert File.read!(context.dets_path) == source_bytes
  end

  test "rolls back every row when one legacy record is invalid", context do
    write_invalid_dets(context.dets_path)

    Repo.delete_all(from(state in ScanState, where: state.name == "notifications"))
    Repo.delete_all(from(effect in Effect, where: effect.operation_key == "like:invalid"))

    assert {:error, {:sqlite_import_failed, _reason}} = Importer.run(context.opts)
    assert is_nil(Repo.get(ScanState, "notifications"))
    assert is_nil(Repo.get(Effect, "like:invalid"))
  end

  test "startup leaves a complete legacy fixture untouched when import is off", context do
    write_dets(context.dets_path)
    {checkpoint_key, _checkpoint_bytes} = write_checkpoint(context.opts)

    Repo.transaction(fn ->
      Repo.delete_all(from(state in ScanState, where: state.name == "notifications"))
      Repo.delete_all(from(effect in Effect, where: effect.operation_key == "like:stable"))
      Repo.delete_all(from(import in LegacyImport, where: import.name == "dets-and-file-v1"))

      assert :ok =
               Startup.run(
                 enabled?: false,
                 settings_import_opts: [env: %{"DELVETOWN_DAILY_REPLY_LIMIT" => "9"}],
                 state_import_opts: context.opts
               )

      assert is_nil(Repo.get(ScanState, "notifications"))
      assert is_nil(Repo.get(Effect, "like:stable"))
      assert is_nil(Repo.get(LegacyImport, "dets-and-file-v1"))
      assert {:error, :not_found} = Jido.Persistence.Ecto.get(checkpoint_key, repo: Repo)

      Repo.rollback(:test_complete)
    end)
  end

  defp write_dets(path) do
    table = __MODULE__.Dets
    {:ok, ^table} = :dets.open_file(table, file: String.to_charlist(path), type: :set)

    :ok = :dets.insert(table, {:cursor, "cursor-1"})

    :ok =
      :dets.insert(
        table,
        {{:seen, "at://seen"}, %{uri: "at://seen", seen_at: "2026-10-05T12:00:00Z"}}
      )

    :ok =
      :dets.insert(
        table,
        {{:effect, "like:stable"},
         %{
           key: "like:stable",
           collection: "town.delve.feed.like",
           rkey: "fixed-rkey",
           status: :complete,
           created_at: "2026-10-05T12:00:00Z",
           completed_at: "2026-10-05T12:01:00Z",
           receipt: %{uri: "at://receipt"}
         }}
      )

    :ok =
      :dets.insert(
        table,
        {{:event, 7}, %{type: :create_record, at: "2026-10-05T12:01:00Z", data: %{result: :ok}}}
      )

    :ok = :dets.close(table)
  end

  defp write_checkpoint(opts) do
    namespace = Keyword.fetch!(opts, :namespace)
    agent_id = Keyword.fetch!(opts, :agent_id)
    path = Keyword.fetch!(opts, :checkpoint_path)
    ref = Jido.Agent.Ref.new!(namespace: namespace, partition: nil, id: agent_id)

    key = Jido.Persistence.agent_key(ref)
    agent = Agent.new!(id: agent_id, state: %{last_run: %{summary: "imported"}})

    :ok =
      Jido.Persistence.save_agent(
        {Jido.Persistence.File, path: path},
        agent,
        namespace: namespace,
        revision: 4
      )

    {:ok, bytes} = Jido.Persistence.File.get(key, path: path)
    {key, bytes}
  end

  defp add_audit_event(path, sequence) do
    table = __MODULE__.ChangedDets
    {:ok, ^table} = :dets.open_file(table, file: String.to_charlist(path), type: :set)

    :ok =
      :dets.insert(
        table,
        {{:event, sequence},
         %{type: :create_record, at: "2026-10-05T12:02:00Z", data: %{result: :ok}}}
      )

    :ok = :dets.close(table)
  end

  defp write_invalid_dets(path) do
    table = __MODULE__.InvalidDets
    {:ok, ^table} = :dets.open_file(table, file: String.to_charlist(path), type: :set)
    :ok = :dets.insert(table, {:cursor, "must-roll-back"})

    :ok =
      :dets.insert(
        table,
        {{:effect, "like:invalid"},
         %{
           key: "like:invalid",
           collection: nil,
           rkey: "invalid-rkey",
           status: :reserved,
           created_at: "2026-10-05T12:00:00Z"
         }}
      )

    :ok = :dets.close(table)
  end
end
