defmodule JidoDelvetown.EffectStore do
  @moduledoc "Owns durable protocol-effect identity, state transitions, and counts."

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.Effect

  @states ["reserved", "uncertain", "completed", "permanent_failure"]

  def get(key, opts \\ []) when is_binary(key) do
    opts |> repo() |> then(& &1.get(Effect, key)) |> effect_map()
  end

  def reserve(key, collection, attributes \\ %{}, opts \\ [])
      when is_binary(key) and is_binary(collection) and is_map(attributes) and is_list(opts) do
    repo = repo(opts)
    reserved_at = now(opts)

    repo.transaction(
      fn ->
        case repo.get(Effect, key) do
          nil -> insert_reserved(repo, key, collection, attributes, reserved_at)
          effect -> validate_reserved(repo, effect, collection, attributes)
        end
      end,
      mode: :immediate
    )
    |> transaction_result()
  end

  def begin_attempt(key, opts \\ []) when is_binary(key) and is_list(opts) do
    repo = repo(opts)

    repo.transaction(
      fn ->
        case repo.get(Effect, key) do
          nil ->
            repo.rollback(:not_found)

          %Effect{status: status} = effect when status in ["reserved", "uncertain"] ->
            effect
            |> Ecto.Changeset.change(
              status: "uncertain",
              attempt_count: effect.attempt_count + 1,
              failure: nil
            )
            |> repo.update!()
            |> effect_map()

          %Effect{status: status} ->
            repo.rollback({:invalid_effect_state, status})
        end
      end,
      mode: :immediate
    )
    |> transaction_result()
  end

  def complete(key, receipt, opts \\ []) when is_binary(key) and is_list(opts) do
    repo = repo(opts)
    completed_at = now(opts)

    repo.transaction(
      fn ->
        case repo.get(Effect, key) do
          nil ->
            repo.rollback(:not_found)

          %Effect{status: "permanent_failure"} ->
            repo.rollback({:invalid_effect_state, "permanent_failure"})

          effect ->
            effect
            |> Ecto.Changeset.change(
              status: "completed",
              completed_at: completed_at,
              receipt: json_safe(receipt),
              failure: nil
            )
            |> repo.update!()
            |> effect_map()
        end
      end,
      mode: :immediate
    )
    |> transaction_result()
  end

  def fail_permanently(key, failure, opts \\ []) when is_binary(key) and is_list(opts) do
    repo = repo(opts)
    completed_at = now(opts)

    repo.transaction(
      fn ->
        case repo.get(Effect, key) do
          nil ->
            repo.rollback(:not_found)

          %Effect{status: "completed"} ->
            repo.rollback({:invalid_effect_state, "completed"})

          effect ->
            effect
            |> Ecto.Changeset.change(
              status: "permanent_failure",
              completed_at: completed_at,
              failure: json_safe(failure),
              receipt: nil
            )
            |> repo.update!()
            |> effect_map()
        end
      end,
      mode: :immediate
    )
    |> transaction_result()
  end

  def counts(opts \\ []) do
    observed =
      repo(opts).all(
        from(effect in Effect,
          group_by: effect.status,
          select: {effect.status, count()}
        )
      )
      |> Map.new()

    Map.new(@states, fn state -> {String.to_existing_atom(state), Map.get(observed, state, 0)} end)
  end

  defp insert_reserved(repo, key, collection, attributes, reserved_at) do
    row = %{
      operation_key: key,
      kind: effect_kind(key),
      collection: collection,
      subject_key: attribute(attributes, :subject_key),
      actor_did: attribute(attributes, :actor_did),
      settings: attribute(attributes, :settings),
      rkey: attribute(attributes, :rkey) || JidoDelvetown.Tid.generate(),
      status: "reserved",
      attempt_count: 0,
      reserved_at: reserved_at,
      inserted_at: reserved_at,
      updated_at: reserved_at
    }

    repo.insert_all(Effect, [row], on_conflict: :nothing, conflict_target: [:operation_key])
    repo.get!(Effect, key) |> effect_map()
  end

  defp validate_reserved(repo, effect, collection, attributes) do
    expected_rkey = attribute(attributes, :rkey)

    cond do
      effect.collection != collection ->
        repo.rollback({:effect_conflict, :collection})

      is_binary(expected_rkey) and effect.rkey != expected_rkey ->
        repo.rollback({:effect_conflict, :rkey})

      true ->
        effect_map(effect)
    end
  end

  defp transaction_result({:ok, value}), do: {:ok, value}
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp effect_map(nil), do: nil

  defp effect_map(%Effect{} = effect) do
    %{
      key: effect.operation_key,
      kind: effect.kind,
      collection: effect.collection,
      subject_key: effect.subject_key,
      actor_did: effect.actor_did,
      settings: effect.settings,
      rkey: effect.rkey,
      status: effect_status(effect.status),
      attempt_count: effect.attempt_count,
      created_at: iso8601(effect.reserved_at),
      completed_at: iso8601(effect.completed_at),
      receipt: effect.receipt,
      failure: effect.failure
    }
  end

  defp effect_status("reserved"), do: :reserved
  defp effect_status("uncertain"), do: :uncertain
  defp effect_status("completed"), do: :completed
  defp effect_status("complete"), do: :completed
  defp effect_status("permanent_failure"), do: :permanent_failure
  defp effect_status(status), do: status

  defp attribute(attributes, key),
    do: Map.get(attributes, key, Map.get(attributes, Atom.to_string(key)))

  defp effect_kind(key) do
    case String.split(key, ":", parts: 2) do
      [kind, _digest] -> kind
      _other -> "effect"
    end
  end

  defp json_safe(nil), do: nil
  defp json_safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%_{} = value), do: value |> Map.from_struct() |> json_safe()
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_safe(item)} end)
  end

  defp json_safe(value), do: inspect(value)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp repo(opts), do: Keyword.get(opts, :repo, Repo)
  defp now(opts), do: Keyword.get_lazy(opts, :now, &utc_now/0)
  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
