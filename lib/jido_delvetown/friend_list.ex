defmodule JidoDelvetown.FriendList do
  @moduledoc "Durable local relationship data for known Delvetown actors."

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{Actor, ActorRelationship}

  @relationship_states ~w(unknown yes no)
  @context_limit 12
  @manual_source "manual"
  @remote_follow_source "remote_follow"

  def add(actor, attrs \\ %{})

  def add(actor, attrs) when is_map(actor) do
    with {:ok, attrs} <- attributes(attrs),
         :ok <- validate_actor(actor),
         {:ok, did} <- actor_did(actor),
         {:ok, relationship_attrs} <- relationship_attrs(attrs) do
      at = now()

      Repo.transaction(
        fn ->
          upsert_actor(did, actor, at)
          upsert_friend(did, relationship_attrs, at)
        end,
        mode: :immediate
      )
      |> result(did)
    end
  end

  def add(_actor, _attrs), do: {:error, :invalid_actor}

  def remove(did) when is_binary(did) and did != "" do
    case Repo.get(ActorRelationship, did) do
      nil ->
        {:error, :not_found}

      relationship ->
        metadata =
          relationship.metadata
          |> remove_friend_source(@manual_source)
          |> Map.put("friend_excluded", true)

        relationship
        |> Ecto.Changeset.change(
          friend: false,
          friend_since: nil,
          metadata: metadata,
          updated_at: now()
        )
        |> Repo.update()
    end
  end

  def remove(_did), do: {:error, :invalid_did}

  def get(did) when is_binary(did) do
    case relationship_query(did) |> Repo.one() do
      {relationship, actor} when relationship.friend -> view(relationship, actor)
      _missing -> nil
    end
  end

  def get(_did), do: nil

  def list do
    Repo.all(
      from([relationship, actor] in base_query(),
        where: relationship.friend,
        order_by: [asc: actor.handle, asc: relationship.actor_did]
      )
    )
    |> Enum.map(fn {relationship, actor} -> view(relationship, actor) end)
  end

  def for_context(opts \\ []) do
    limit = opts |> Keyword.get(:limit, @context_limit) |> max(0) |> min(@context_limit)

    Repo.all(
      from([relationship, actor] in base_query(),
        where: relationship.friend and not relationship.do_not_mention and not actor.opted_out,
        order_by: [asc: relationship.last_referenced_at, asc: actor.handle],
        limit: ^limit
      )
    )
    |> Enum.map(fn {relationship, actor} ->
      %{
        did: actor.did,
        handle: actor.handle,
        display_name: actor.display_name,
        topics: topic_list(relationship.topics),
        follows_agent: relationship.follows_agent,
        agent_follows: relationship.agent_follows
      }
    end)
  end

  def record_reference(did) when is_binary(did) and did != "" do
    at = now()

    {count, _rows} =
      Repo.update_all(
        from(relationship in ActorRelationship,
          where: relationship.actor_did == ^did and relationship.friend
        ),
        set: [last_referenced_at: at, last_related_at: at, updated_at: at],
        inc: [reference_count: 1]
      )

    case count do
      1 -> {:ok, get(did)}
      0 -> {:error, :not_found}
    end
  end

  def record_reference(_did), do: {:error, :invalid_did}

  def record_text_references(text) when is_binary(text) do
    handles =
      ~r/@([[:alnum:]._-]+)/u
      |> Regex.scan(text, capture: :all_but_first)
      |> List.flatten()
      |> MapSet.new(&(String.trim_trailing(&1, ".") |> String.downcase()))

    list()
    |> Enum.filter(fn friend ->
      is_binary(friend.handle) and MapSet.member?(handles, String.downcase(friend.handle))
    end)
    |> Enum.reduce_while(:ok, fn friend, :ok ->
      case record_reference(friend.did) do
        {:ok, _friend} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def record_text_references(_text), do: :ok

  def sync_following(actors, opts \\ [])

  def sync_following(actors, opts) when is_list(actors) do
    at = opts |> Keyword.get(:at) |> parse_time()

    with {:ok, actors} <- normalize_sync_actors(actors) do
      Repo.transaction(
        fn ->
          synced_dids = MapSet.new(actors, &value(&1, :did))

          added =
            Enum.count(actors, fn actor ->
              did = value(actor, :did)
              upsert_actor(did, actor, at)
              upsert_remote_friend(did, at)
            end)

          removed = reconcile_remote_friends(synced_dids, at)

          %{seen: MapSet.size(synced_dids), added: added, removed: removed}
        end,
        mode: :immediate
      )
    end
  end

  def sync_following(_actors, _opts), do: {:error, :invalid_actors}

  def record_follows_agent(did, at \\ nil),
    do: set_relationship_state(did, :follows_agent, "yes", at)

  def record_agent_follows(did, at \\ nil),
    do: set_relationship_state(did, :agent_follows, "yes", at)

  defp set_relationship_state(did, field, state, at)
       when is_binary(did) and field in [:follows_agent, :agent_follows] do
    if valid_did?(did) do
      at = parse_time(at)

      Repo.transaction(
        fn ->
          upsert_actor(did, %{did: did}, at)
          upsert_relationship_state(did, field, state, at)
        end,
        mode: :immediate
      )
    else
      {:error, :invalid_did}
    end
  end

  defp set_relationship_state(_did, _field, _state, _at), do: {:error, :invalid_did}

  defp upsert_actor(did, actor_attrs, at) do
    case Repo.get(Actor, did) do
      nil ->
        %Actor{
          did: did,
          handle: value(actor_attrs, :handle),
          display_name: value(actor_attrs, :display_name),
          profile: json_safe(actor_attrs),
          first_seen_at: at,
          last_seen_at: at,
          metadata: %{}
        }
        |> Repo.insert!()

      actor ->
        actor
        |> Ecto.Changeset.change(
          handle: value(actor_attrs, :handle) || actor.handle,
          display_name: value(actor_attrs, :display_name) || actor.display_name,
          profile: Map.merge(actor.profile || %{}, json_safe(actor_attrs)),
          last_seen_at: max_time(actor.last_seen_at, at)
        )
        |> Repo.update!()
    end
  end

  defp upsert_friend(did, attrs, at) do
    case Repo.get(ActorRelationship, did) do
      nil ->
        %ActorRelationship{
          actor_did: did,
          friend: true,
          follows_agent: Map.get(attrs, :follows_agent, "unknown"),
          agent_follows: Map.get(attrs, :agent_follows, "unknown"),
          topics: Map.get(attrs, :topics, %{}),
          notes: Map.get(attrs, :notes),
          do_not_mention: Map.get(attrs, :do_not_mention, false),
          friend_since: at,
          first_related_at: at,
          last_related_at: at,
          metadata: add_friend_source(%{}, @manual_source)
        }
        |> Repo.insert!()

      relationship ->
        metadata =
          relationship.metadata
          |> add_friend_source(@manual_source)
          |> Map.delete("friend_excluded")

        relationship
        |> Ecto.Changeset.change(
          friend: true,
          follows_agent: Map.get(attrs, :follows_agent, relationship.follows_agent),
          agent_follows: Map.get(attrs, :agent_follows, relationship.agent_follows),
          topics: Map.get(attrs, :topics, relationship.topics),
          notes: Map.get(attrs, :notes, relationship.notes),
          do_not_mention: Map.get(attrs, :do_not_mention, relationship.do_not_mention),
          friend_since: relationship.friend_since || at,
          last_related_at: at,
          metadata: metadata
        )
        |> Repo.update!()
    end
  end

  defp upsert_remote_friend(did, at) do
    case Repo.get(ActorRelationship, did) do
      nil ->
        %ActorRelationship{
          actor_did: did,
          friend: true,
          follows_agent: "unknown",
          agent_follows: "yes",
          topics: %{},
          do_not_mention: false,
          friend_since: at,
          first_related_at: at,
          last_related_at: at,
          reference_count: 0,
          metadata:
            %{}
            |> add_friend_source(@remote_follow_source)
            |> mark_follow_sync(at)
        }
        |> Repo.insert!()

        true

      relationship ->
        new_source? = @remote_follow_source not in friend_sources(relationship.metadata)

        metadata =
          relationship.metadata
          |> add_friend_source(@remote_follow_source)
          |> mark_follow_sync(at)

        friend? = not Map.get(metadata, "friend_excluded", false)

        relationship
        |> Ecto.Changeset.change(
          friend: friend?,
          agent_follows: "yes",
          friend_since: if(friend?, do: relationship.friend_since || at),
          last_related_at: at,
          metadata: metadata
        )
        |> Repo.update!()

        new_source?
    end
  end

  defp reconcile_remote_friends(synced_dids, at) do
    stale =
      ActorRelationship
      |> Repo.all()
      |> Enum.filter(fn relationship ->
        @remote_follow_source in friend_sources(relationship.metadata) and
          not MapSet.member?(synced_dids, relationship.actor_did)
      end)

    Enum.each(stale, fn relationship ->
      metadata =
        relationship.metadata
        |> remove_friend_source(@remote_follow_source)
        |> mark_follow_sync(at)

      friend? =
        friend_sources(metadata) != [] and not Map.get(metadata, "friend_excluded", false)

      relationship
      |> Ecto.Changeset.change(
        friend: friend?,
        agent_follows: "no",
        friend_since: if(friend?, do: relationship.friend_since, else: nil),
        last_related_at: at,
        metadata: metadata
      )
      |> Repo.update!()
    end)

    length(stale)
  end

  defp upsert_relationship_state(did, field, state, at) do
    case Repo.get(ActorRelationship, did) do
      nil ->
        struct!(ActorRelationship, %{
          field => state,
          actor_did: did,
          first_related_at: at,
          last_related_at: at,
          metadata: %{}
        })
        |> Repo.insert!()

      relationship ->
        relationship
        |> Ecto.Changeset.change(%{field => state, last_related_at: at})
        |> Repo.update!()
    end
  end

  defp relationship_attrs(attrs) do
    with {:ok, follows_agent} <- optional_state(attrs, :follows_agent),
         {:ok, agent_follows} <- optional_state(attrs, :agent_follows),
         {:ok, topics} <- optional_topics(attrs),
         {:ok, notes} <- optional_notes(attrs),
         {:ok, do_not_mention} <- optional_boolean(attrs, :do_not_mention) do
      {:ok,
       %{}
       |> maybe_put(:follows_agent, follows_agent)
       |> maybe_put(:agent_follows, agent_follows)
       |> maybe_put(:topics, topics)
       |> maybe_put_present(:notes, notes)
       |> maybe_put_present(:do_not_mention, do_not_mention)}
    end
  end

  defp optional_state(attrs, key) do
    case Map.fetch(attrs, key) do
      :error -> {:ok, nil}
      {:ok, value} when value in @relationship_states -> {:ok, value}
      {:ok, value} when value in [:unknown, :yes, :no] -> {:ok, Atom.to_string(value)}
      {:ok, true} -> {:ok, "yes"}
      {:ok, false} -> {:ok, "no"}
      {:ok, _value} -> {:error, {:invalid_relationship_state, key}}
    end
  end

  defp optional_topics(attrs) do
    case Map.fetch(attrs, :topics) do
      :error ->
        {:ok, nil}

      {:ok, topics} when is_list(topics) and length(topics) <= 20 ->
        if Enum.all?(topics, &valid_topic?/1) do
          {:ok, topics |> Enum.map(&String.trim/1) |> Enum.uniq() |> Map.new(&{&1, true})}
        else
          {:error, :invalid_topics}
        end

      {:ok, _topics} ->
        {:error, :invalid_topics}
    end
  end

  defp optional_notes(attrs) do
    case Map.fetch(attrs, :notes) do
      :error -> {:ok, :not_set}
      {:ok, value} when is_binary(value) and byte_size(value) <= 2_000 -> {:ok, value}
      {:ok, nil} -> {:ok, nil}
      {:ok, _value} -> {:error, :invalid_notes}
    end
  end

  defp optional_boolean(attrs, key) do
    case Map.fetch(attrs, key) do
      :error -> {:ok, :not_set}
      {:ok, value} when is_boolean(value) -> {:ok, value}
      {:ok, _value} -> {:error, {:invalid_boolean, key}}
    end
  end

  defp actor_did(actor) do
    case value(actor, :did) do
      did when is_binary(did) -> if(valid_did?(did), do: {:ok, did}, else: {:error, :invalid_did})
      _invalid -> {:error, :invalid_did}
    end
  end

  defp valid_did?("did:" <> rest), do: rest != ""
  defp valid_did?(_did), do: false

  defp validate_actor(actor) do
    if valid_optional_text?(value(actor, :handle), 253) and
         valid_optional_text?(value(actor, :display_name), 256) do
      :ok
    else
      {:error, :invalid_actor}
    end
  end

  defp valid_optional_text?(nil, _limit), do: true

  defp valid_optional_text?(value, limit),
    do: is_binary(value) and value != "" and String.length(value) <= limit

  defp valid_topic?(value),
    do: is_binary(value) and String.trim(value) != "" and String.length(value) <= 80

  defp normalize_sync_actors(actors) do
    actors
    |> Enum.reduce_while({:ok, %{}}, fn actor, {:ok, normalized} ->
      with true <- is_map(actor),
           :ok <- validate_actor(actor),
           {:ok, did} <- actor_did(actor) do
        {:cont, {:ok, Map.put(normalized, did, actor)}}
      else
        _invalid -> {:halt, {:error, :invalid_actor}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Map.values(normalized)}
      {:error, _reason} = error -> error
    end
  end

  defp add_friend_source(metadata, source) do
    metadata = metadata || %{}

    Map.put(metadata, "friend_sources", Enum.sort(Enum.uniq([source | friend_sources(metadata)])))
  end

  defp remove_friend_source(metadata, source) do
    metadata = metadata || %{}
    Map.put(metadata, "friend_sources", List.delete(friend_sources(metadata), source))
  end

  defp friend_sources(metadata) when is_map(metadata) do
    case Map.get(metadata, "friend_sources", []) do
      sources when is_list(sources) -> Enum.filter(sources, &is_binary/1)
      _invalid -> []
    end
  end

  defp friend_sources(_metadata), do: []

  defp mark_follow_sync(metadata, at),
    do: Map.put(metadata || %{}, "last_follow_sync_at", DateTime.to_iso8601(at))

  defp result({:ok, _relationship}, did), do: {:ok, get(did)}
  defp result({:error, reason}, _did), do: {:error, reason}

  defp relationship_query(did) do
    from([relationship, _actor] in base_query(), where: relationship.actor_did == ^did)
  end

  defp base_query do
    from(relationship in ActorRelationship,
      join: actor in Actor,
      on: actor.did == relationship.actor_did,
      select: {relationship, actor}
    )
  end

  defp view(relationship, actor) do
    %{
      did: actor.did,
      handle: actor.handle,
      display_name: actor.display_name,
      friend: relationship.friend,
      follows_agent: relationship.follows_agent,
      agent_follows: relationship.agent_follows,
      topics: topic_list(relationship.topics),
      notes: relationship.notes,
      do_not_mention: relationship.do_not_mention,
      friend_since: iso8601(relationship.friend_since),
      last_referenced_at: iso8601(relationship.last_referenced_at),
      reference_count: relationship.reference_count
    }
  end

  defp topic_list(topics) when is_map(topics), do: topics |> Map.keys() |> Enum.sort()
  defp topic_list(_topics), do: []

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_present(map, _key, :not_set), do: map
  defp maybe_put_present(map, key, value), do: Map.put(map, key, value)

  defp attributes(attrs) when is_map(attrs), do: {:ok, atomize_known_keys(attrs)}

  defp attributes(attrs) when is_list(attrs),
    do: {:ok, attrs |> Map.new() |> atomize_known_keys()}

  defp attributes(_attrs), do: {:error, :invalid_relationship}

  defp atomize_known_keys(attrs) do
    Map.new(attrs, fn
      {"follows_agent", value} -> {:follows_agent, value}
      {"agent_follows", value} -> {:agent_follows, value}
      {"topics", value} -> {:topics, value}
      {"notes", value} -> {:notes, value}
      {"do_not_mention", value} -> {:do_not_mention, value}
      item -> item
    end)
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp max_time(nil, right), do: right
  defp max_time(left, right), do: if(DateTime.compare(left, right) == :lt, do: right, else: left)

  defp parse_time(%DateTime{} = value), do: microsecond(value)

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> microsecond(time)
      _invalid -> now()
    end
  end

  defp parse_time(_value), do: now()

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp microsecond(value) do
    value |> DateTime.to_unix(:microsecond) |> DateTime.from_unix!(:microsecond)
  end

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_safe(item)} end)
  end

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value), do: value

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
