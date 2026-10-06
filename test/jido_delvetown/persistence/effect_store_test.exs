defmodule JidoDelvetown.EffectStoreTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.{EffectStore, Repo}
  alias JidoDelvetown.Storage.Effect

  setup do
    Repo.delete_all(Effect)
    :ok
  end

  test "returns one record key for one effect identity" do
    assert {:ok, first} = EffectStore.reserve("same", "town.delve.feed.like")
    assert {:ok, second} = EffectStore.reserve("same", "town.delve.feed.like")
    assert first.rkey == second.rkey

    assert {:ok, complete} = EffectStore.complete("same", %{uri: "at://receipt"})
    assert complete.status == :completed

    assert EffectStore.counts() == %{
             reserved: 0,
             uncertain: 0,
             completed: 1,
             permanent_failure: 0
           }
  end

  test "concurrent reservations obtain one effect identity" do
    effects =
      1..20
      |> Task.async_stream(
        fn _index -> EffectStore.reserve("concurrent", "town.delve.feed.like") end,
        max_concurrency: 20,
        ordered: false
      )
      |> Enum.map(fn {:ok, {:ok, effect}} -> effect end)

    assert effects |> Enum.map(& &1.rkey) |> Enum.uniq() |> length() == 1
    assert Repo.aggregate(Effect, :count, :operation_key) == 1
  end

  test "enforces legal terminal transitions" do
    assert {:ok, _effect} = EffectStore.reserve("complete", "town.delve.feed.post")
    assert {:ok, %{status: :uncertain}} = EffectStore.begin_attempt("complete")
    assert {:ok, %{status: :completed}} = EffectStore.complete("complete", %{uri: "at://one"})

    assert {:error, {:invalid_effect_state, "completed"}} =
             EffectStore.fail_permanently("complete", %{reason: :late_failure})

    assert {:ok, _effect} = EffectStore.reserve("failed", "town.delve.feed.post")
    assert {:ok, %{status: :uncertain}} = EffectStore.begin_attempt("failed")

    assert {:ok, %{status: :permanent_failure}} =
             EffectStore.fail_permanently("failed", %{reason: :forbidden})

    assert {:error, {:invalid_effect_state, "permanent_failure"}} =
             EffectStore.complete("failed", %{uri: "at://late"})
  end

  test "rejects a conflicting collection or fixed record key" do
    assert {:ok, effect} =
             EffectStore.reserve("stable", "town.delve.feed.post", %{rkey: "fixed"})

    assert effect.rkey == "fixed"

    assert {:error, {:effect_conflict, :collection}} =
             EffectStore.reserve("stable", "town.delve.feed.like")

    assert {:error, {:effect_conflict, :rkey}} =
             EffectStore.reserve("stable", "town.delve.feed.post", %{rkey: "other"})
  end
end
