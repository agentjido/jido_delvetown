defmodule JidoDelvetown.ActorMemory do
  @moduledoc "Owns durable actor identity and contact memory."

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.Actor

  def get(did, opts \\ []), do: repo(opts).get(Actor, did)

  def remember(candidate, cycle, decision, at, opts \\ [])

  def remember(%{author: %{did: did} = author} = candidate, cycle, decision, at, opts)
      when is_binary(did) do
    repo = repo(opts)
    seen_at = parse_time(at)
    contacted? = cycle.status in ["acted", "simulated"]
    opted_out? = Map.get(candidate, :opt_out?, false)
    welcome_status = welcome_status(cycle, decision, contacted?)

    repo.transaction(
      fn ->
        case repo.get(Actor, did) do
          nil ->
            %Actor{
              did: did,
              handle: Map.get(author, :handle),
              display_name: Map.get(author, :display_name),
              profile: json_safe(author),
              first_seen_at: seen_at,
              last_seen_at: seen_at,
              last_interaction_at: if(contacted?, do: seen_at),
              contact_count: if(contacted?, do: 1, else: 0),
              welcome_status: welcome_status,
              opted_out: opted_out?,
              metadata: actor_metadata(%{}, candidate, seen_at)
            }
            |> repo.insert!()

          actor ->
            actor
            |> Ecto.Changeset.change(
              handle: Map.get(author, :handle) || actor.handle,
              display_name: Map.get(author, :display_name) || actor.display_name,
              profile: Map.merge(actor.profile || %{}, json_safe(author)),
              last_seen_at: seen_at,
              last_interaction_at: if(contacted?, do: seen_at, else: actor.last_interaction_at),
              contact_count: actor.contact_count + if(contacted?, do: 1, else: 0),
              welcome_status: welcome_status || actor.welcome_status,
              opted_out: actor.opted_out || opted_out?,
              metadata: actor_metadata(actor.metadata || %{}, candidate, seen_at)
            )
            |> repo.update!()
        end
      end,
      mode: :immediate
    )
    |> transaction_ok()
  end

  def remember(_candidate, _cycle, _decision, _at, _opts), do: :ok

  def remember_social_signal(candidate, cycle, opts \\ [])

  def remember_social_signal(%{reason: "like"} = candidate, cycle, opts) do
    observed_at = candidate.indexed_at || now()
    ignored_cycle = %{cycle | candidate: candidate, status: "ignored"}
    remember(candidate, ignored_cycle, %{action: "skip"}, observed_at, opts)
  end

  def remember_social_signal(_candidate, _cycle, _opts), do: :ok

  def context(did, opts \\ [])

  def context(did, opts) when is_binary(did) do
    did
    |> get(opts)
    |> actor_context()
  end

  def context(_did, _opts), do: nil

  defp actor_metadata(metadata, %{reason: "like", event_key: event_key}, observed_at)
       when is_binary(event_key) do
    entry = %{
      "event_key" => event_key,
      "observed_at" => DateTime.to_iso8601(observed_at)
    }

    prior_likes =
      metadata
      |> Map.get("incoming_likes", [])
      |> List.wrap()
      |> Enum.filter(&is_map/1)

    likes =
      [entry | prior_likes]
      |> Enum.uniq_by(&Map.get(&1, "event_key"))
      |> Enum.take(20)

    Map.put(metadata, "incoming_likes", likes)
  end

  defp actor_metadata(metadata, _candidate, _observed_at), do: metadata

  defp welcome_status(%{status: "simulated"}, %{action: "welcome"}, true), do: "simulated"
  defp welcome_status(_cycle, %{action: "welcome"}, true), do: "completed"
  defp welcome_status(_cycle, _decision, _contacted?), do: nil

  defp actor_context(nil), do: nil

  defp actor_context(actor) do
    %{
      did: actor.did,
      handle: actor.handle,
      display_name: actor.display_name,
      first_seen_at: iso8601(actor.first_seen_at),
      last_interaction_at: iso8601(actor.last_interaction_at),
      contact_count: actor.contact_count,
      welcome_status: actor.welcome_status,
      opted_out: actor.opted_out
    }
  end

  defp parse_time(%DateTime{} = value), do: microsecond(value)

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> microsecond(time)
      _error -> now()
    end
  end

  defp parse_time(_value), do: now()

  defp microsecond(value) do
    value |> DateTime.to_unix(:microsecond) |> DateTime.from_unix!(:microsecond)
  end

  defp json_safe(nil), do: nil
  defp json_safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_safe(item)} end)
  end

  defp json_safe(value), do: inspect(value)

  defp transaction_ok({:ok, _value}), do: :ok
  defp transaction_ok({:error, reason}), do: {:error, reason}

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp repo(opts), do: Keyword.get(opts, :repo, Repo)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
