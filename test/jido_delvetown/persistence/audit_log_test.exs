defmodule JidoDelvetown.AuditLogTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{AuditLog, Repo}
  alias JidoDelvetown.Storage.AuditEvent

  defmodule FailingRepo do
    def insert(%AuditEvent{}), do: {:error, :write_failed}
  end

  setup do
    Repo.delete_all(AuditEvent)
    :ok
  end

  test "returns a write failure to the caller" do
    assert {:error, :write_failed} =
             AuditLog.record(:decision, %{result: :ok},
               repo: FailingRepo,
               now: ~U[2026-10-05 12:00:00.000000Z]
             )
  end

  test "returns recent events in descending durable sequence" do
    first_at = ~U[2026-10-05 12:00:00.000000Z]
    second_at = ~U[2026-10-05 12:01:00.000000Z]

    assert :ok = AuditLog.record(:first, %{result: :ok}, now: first_at)
    assert :ok = AuditLog.record(:second, %{result: :error}, now: second_at)

    assert [
             %{
               type: :second,
               at: "2026-10-05T12:01:00.000000Z",
               data: %{result: "error"},
               sequence: second_sequence
             },
             %{
               type: :first,
               at: "2026-10-05T12:00:00.000000Z",
               data: %{result: "ok"},
               sequence: first_sequence
             }
           ] = AuditLog.recent(2)

    assert second_sequence == first_sequence + 1
  end

  test "counts reconciled create and delete events" do
    assert :ok = AuditLog.record(:create_record, %{reconciled?: true})
    assert :ok = AuditLog.record(:delete_record, %{reconciled?: true})
    assert :ok = AuditLog.record(:create_record, %{reconciled?: false})
    assert :ok = AuditLog.record(:query, %{reconciled?: true})

    assert AuditLog.reconciled_effect_count() == 2
  end
end
