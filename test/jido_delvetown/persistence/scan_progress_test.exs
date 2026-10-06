defmodule JidoDelvetown.ScanProgressTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{Repo, ScanProgress}
  alias JidoDelvetown.Storage.ScanState

  setup do
    Repo.delete_all(ScanState)
    :ok
  end

  test "one scan stream has one active claim" do
    assert {:ok, notification_scan} = ScanProgress.claim("notifications")
    assert {:error, :scan_in_progress} = ScanProgress.claim("notifications")

    assert {:ok, member_scan} = ScanProgress.claim("members")
    assert member_scan.name == "members"

    assert {:ok, completed} =
             ScanProgress.finish("notifications", notification_scan.token, "cursor-2")

    assert completed.cursor == "cursor-2"
    assert {:ok, next_scan} = ScanProgress.claim("notifications")
    assert next_scan.cursor == "cursor-2"

    assert {:ok, _scan} = ScanProgress.release("notifications", next_scan.token)
    assert {:ok, _scan} = ScanProgress.release("members", member_scan.token)
  end

  test "an expired claim can resume after a delayed cycle" do
    first_time = ~U[2026-10-05 12:00:00.000000Z]
    delayed_time = ~U[2026-10-05 12:02:00.000000Z]

    assert {:ok, first} =
             ScanProgress.claim("notifications", now: first_time, lease_ms: 60_000)

    assert {:error, :scan_in_progress} =
             ScanProgress.claim("notifications",
               now: DateTime.add(first_time, 30, :second),
               lease_ms: 60_000
             )

    assert {:ok, delayed} =
             ScanProgress.claim("notifications", now: delayed_time, lease_ms: 60_000)

    refute delayed.token == first.token

    assert {:error, :stale_scan_claim} =
             ScanProgress.finish("notifications", first.token, "stale", now: delayed_time)

    assert {:ok, _scan} =
             ScanProgress.finish("notifications", delayed.token, "resumed", now: delayed_time)
  end

  test "member discovery watermarks use the same durable scan state" do
    assert {:ok, %{cursor: "member-42"}} =
             ScanProgress.put_cursor("members", "member-42")

    assert %{cursor: "member-42", metadata: metadata} = ScanProgress.get("members")
    assert metadata == %{}
  end
end
