defmodule JidoDelvetown.AuditLog do
  @moduledoc "Owns durable audit-event writes, reads, and counts."

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.AuditEvent

  def record(type, data, opts \\ []) do
    repo = repo(opts)

    result =
      %AuditEvent{
        type: to_string(type),
        data: json_safe(data) || %{},
        occurred_at: now(opts)
      }
      |> repo.insert()

    if match?({:ok, _event}, result), do: :ok, else: result
  end

  def recent(limit \\ 25, opts \\ []) do
    repo(opts).all(
      from(event in AuditEvent,
        order_by: [desc: event.id],
        limit: ^max(limit, 0)
      )
    )
    |> Enum.map(&event_map/1)
  end

  def reconciled_effect_count(opts \\ []) do
    repo(opts).aggregate(
      from(event in AuditEvent,
        where:
          event.type in ["create_record", "delete_record"] and
            fragment(
              "json_extract(?, '$.' || 'reconciled' || char(63)) = 1",
              event.data
            )
      ),
      :count,
      :id
    )
  end

  defp event_map(%AuditEvent{} = event) do
    %{
      sequence: event.id,
      type: existing_atom(event.type),
      at: iso8601(event.occurred_at),
      data: existing_atom_keys(event.data)
    }
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

  defp existing_atom_keys(value) when is_list(value), do: Enum.map(value, &existing_atom_keys/1)

  defp existing_atom_keys(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {existing_atom(key), existing_atom_keys(item)} end)
  end

  defp existing_atom_keys(value), do: value

  defp existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp existing_atom(value), do: value

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp repo(opts), do: Keyword.get(opts, :repo, Repo)
  defp now(opts), do: Keyword.get_lazy(opts, :now, &utc_now/0)
  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
