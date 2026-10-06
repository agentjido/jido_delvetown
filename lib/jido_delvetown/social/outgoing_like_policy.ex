defmodule JidoDelvetown.OutgoingLikePolicy do
  @moduledoc "Applies deterministic eligibility rules before an outgoing like decision."

  alias JidoDelvetown.{InteractionEvents, OptOut, Protocol, Repo, Session}
  alias JidoDelvetown.Settings.Limits
  alias JidoDelvetown.Storage.Effect

  @unsafe_labels ~w(
    !hide graphic-media hate nudity porn scam self-harm sexual spam threat
  )
  @unsafe_text_markers [
    "ignore previous instructions",
    "ignore the system",
    "reveal credentials",
    "reveal your password",
    "show your system prompt"
  ]
  @temporary_reasons ["like_budget_exhausted", "actor_like_cooldown"]

  def evaluate(candidate, state, opts \\ [])

  def evaluate(candidate, state, opts) when is_map(candidate) and is_map(state) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, limits} <- limits(opts),
         :ok <- valid_subject(candidate),
         :ok <- exclude_owned_post(candidate, opts),
         :ok <- exclude_already_liked(candidate, opts),
         :ok <- exclude_duplicate(candidate, state, opts),
         :ok <- exclude_opted_out_actor(candidate),
         :ok <- exclude_blocked_actor(candidate),
         :ok <- exclude_stale_candidate(candidate, now, limits, opts),
         :ok <- require_safe_content(candidate),
         :ok <- enforce_budget(state, now, limits, opts),
         :ok <- enforce_actor_cooldown(candidate, now, limits, opts) do
      :ok
    end
  end

  def evaluate(_candidate, _state, _opts), do: {:skip, "invalid_like_subject"}

  def temporary_reason?(reason), do: reason in @temporary_reasons

  defp valid_subject(%{uri: uri, cid: cid})
       when is_binary(uri) and is_binary(cid) and cid != "" do
    if Regex.match?(~r/\Aat:\/\/[^\/\s]+\/town\.delve\.feed\.post\/[^\/\s]+\z/, uri),
      do: :ok,
      else: {:skip, "invalid_like_subject"}
  end

  defp valid_subject(_candidate), do: {:skip, "invalid_like_subject"}

  defp exclude_owned_post(candidate, opts) do
    case {get_in(candidate, [:author, :did]), agent_did(opts)} do
      {did, did} when is_binary(did) -> {:skip, "own_post"}
      _identity -> :ok
    end
  end

  defp exclude_already_liked(candidate, opts) do
    liked? = present?(get_in(candidate, [:viewer, :like]))

    local_effect? =
      case Keyword.fetch(opts, :local_effect?) do
        {:ok, value} -> value
        :error -> local_like_effect?(candidate.uri)
      end

    if liked? or local_effect?, do: {:skip, "already_liked"}, else: :ok
  end

  defp exclude_duplicate(candidate, state, opts) do
    processed = get_in(state, [:notifications, :processed]) || %{}
    record = Map.get(processed, candidate.id) || Map.get(processed, candidate.uri)

    case record do
      %{status: "failed"} -> :ok
      %{"status" => "failed"} -> :ok
      %{status: "proposed"} -> allow_proposed(opts)
      %{"status" => "proposed"} -> allow_proposed(opts)
      nil -> :ok
      _record -> {:skip, "duplicate_candidate"}
    end
  end

  defp allow_proposed(opts) do
    if Keyword.get(opts, :allow_proposed?, false),
      do: :ok,
      else: {:skip, "duplicate_candidate"}
  end

  defp exclude_opted_out_actor(candidate) do
    opted_out? = get_in(candidate, [:memory, :actor, :opted_out]) == true

    if opted_out? or OptOut.requested?(Map.get(candidate, :text, "")),
      do: {:skip, "actor_opted_out"},
      else: :ok
  end

  defp exclude_blocked_actor(candidate) do
    viewer = get_in(candidate, [:author, :viewer]) || %{}
    blocked? = Map.get(viewer, :blocked_by) == true or present?(Map.get(viewer, :blocking))

    if blocked?, do: {:skip, "actor_blocked"}, else: :ok
  end

  defp exclude_stale_candidate(%{indexed_at: indexed_at}, now, limits, opts)
       when is_binary(indexed_at) do
    max_age = Keyword.get(opts, :max_age_hours, limits.like_candidate_max_age_hours)

    case DateTime.from_iso8601(indexed_at) do
      {:ok, timestamp, _offset} ->
        if DateTime.diff(now, timestamp, :hour) > max_age,
          do: {:skip, "stale_candidate"},
          else: :ok

      _invalid ->
        {:skip, "stale_candidate"}
    end
  end

  defp exclude_stale_candidate(_candidate, _now, _limits, _opts),
    do: {:skip, "stale_candidate"}

  defp require_safe_content(candidate) do
    text = Map.get(candidate, :text, "")

    labels =
      List.wrap(Map.get(candidate, :labels)) ++ List.wrap(get_in(candidate, [:author, :labels]))

    unsafe_label? =
      Enum.any?(labels, fn label ->
        is_binary(label) and String.downcase(label) in @unsafe_labels
      end)

    unsafe_text? =
      if is_binary(text) do
        normalized = String.downcase(text)

        String.trim(text) == "" or
          Enum.any?(@unsafe_text_markers, &String.contains?(normalized, &1))
      else
        true
      end

    if unsafe_label? or unsafe_text?, do: {:skip, "unsafe_content"}, else: :ok
  end

  defp enforce_budget(state, now, limits, opts) do
    count =
      case Keyword.fetch(opts, :daily_like_count) do
        {:ok, value} -> value
        :error -> daily_like_count(state, now, opts)
      end

    if is_integer(count) and count < limits.daily_like_limit,
      do: :ok,
      else: {:skip, "like_budget_exhausted"}
  end

  defp enforce_actor_cooldown(candidate, now, limits, opts) do
    in_cooldown? =
      case Keyword.fetch(opts, :actor_in_cooldown?) do
        {:ok, value} -> value
        :error -> actor_in_cooldown?(get_in(candidate, [:author, :did]), now, limits, opts)
      end

    if in_cooldown?, do: {:skip, "actor_like_cooldown"}, else: :ok
  end

  defp daily_like_count(state, now, opts) do
    state_count = get_in(state, [:budget, :likes]) || 0
    start_of_day = DateTime.new!(DateTime.to_date(now), ~T[00:00:00], "Etc/UTC")

    ledger_count =
      InteractionEvents.outreach_count(
        "like",
        start_of_day,
        exclude_event_key: Keyword.get(opts, :exclude_event_key)
      )

    max(state_count, ledger_count)
  end

  defp actor_in_cooldown?(did, now, limits, opts) when is_binary(did) do
    since = DateTime.add(now, -limits.like_actor_cooldown_hours, :hour)

    InteractionEvents.recent_outreach_for_actor?(
      "like",
      did,
      since,
      exclude_event_key: Keyword.get(opts, :exclude_event_key)
    )
  end

  defp actor_in_cooldown?(_did, _now, _limits, _opts), do: true

  defp limits(opts) do
    case Keyword.fetch(opts, :limits) do
      {:ok, limits} when is_map(limits) -> {:ok, limits}
      {:ok, _invalid} -> {:skip, "limit_settings_unavailable"}
      :error -> load_limits()
    end
  end

  defp load_limits do
    case Limits.current() do
      {:ok, limits} -> {:ok, limits}
      {:error, _reason} -> {:skip, "limit_settings_unavailable"}
    end
  end

  defp local_like_effect?(uri) when is_binary(uri) do
    case Repo.get(Effect, Protocol.effect_key("like", [uri])) do
      %Effect{status: status} when status in ["reserved", "uncertain", "completed"] -> true
      _effect -> false
    end
  end

  defp local_like_effect?(_uri), do: false

  defp agent_did(opts) do
    case Keyword.fetch(opts, :agent_did) do
      {:ok, did} -> did
      :error -> session_did()
    end
  end

  defp session_did do
    case Session.status() do
      %{did: did} when is_binary(did) -> did
      _status -> nil
    end
  catch
    :exit, _reason -> nil
  end

  defp present?(value), do: is_binary(value) and value != ""
end
