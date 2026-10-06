defmodule JidoDelvetown.DraftReviews do
  @moduledoc "Stores one durable operator decision for each local draft."

  import Ecto.Query

  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{DraftReview, ImageDraft, InteractionEvent}

  @kinds ~w(text like image)
  @decisions ~w(approved rejected)
  @text_actions ~w(post reply welcome)

  @spec decide(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def decide(kind, source_key, decision, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    with :ok <- validate_input(kind, source_key, decision),
         :ok <- validate_source(repo, kind, source_key) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      row = %{
        review_key: review_key(kind, source_key),
        kind: kind,
        source_key: source_key,
        decision: decision,
        reviewed_at: now,
        inserted_at: now,
        updated_at: now
      }

      repo.insert_all(DraftReview, [row],
        conflict_target: [:review_key],
        on_conflict: {:replace, [:decision, :reviewed_at, :updated_at]}
      )

      {:ok, repo.get!(DraftReview, row.review_key)}
    end
  rescue
    error -> {:error, {:review_failed, Exception.message(error)}}
  end

  @spec get(String.t(), String.t(), keyword()) :: struct() | nil
  def get(kind, source_key, opts \\ [])

  def get(kind, source_key, opts) when is_binary(kind) and is_binary(source_key) do
    repo = Keyword.get(opts, :repo, Repo)
    repo.get(DraftReview, review_key(kind, source_key))
  end

  def get(_kind, _source_key, _opts), do: nil

  @spec approved?(String.t(), String.t(), keyword()) :: boolean()
  def approved?(kind, source_key, opts \\ []) do
    match?(%DraftReview{decision: "approved"}, get(kind, source_key, opts))
  end

  @spec decisions(keyword()) :: %{{String.t(), String.t()} => map()}
  def decisions(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    query =
      case Keyword.fetch(opts, :sources) do
        {:ok, sources} when is_list(sources) ->
          review_keys =
            Enum.map(sources, fn {kind, source_key} -> review_key(kind, source_key) end)

          from(review in DraftReview, where: review.review_key in ^review_keys)

        _option ->
          DraftReview
      end

    repo.all(
      from(review in query,
        select: %{
          kind: review.kind,
          source_key: review.source_key,
          decision: review.decision,
          reviewed_at: review.reviewed_at
        }
      )
    )
    |> Map.new(fn review ->
      {{review.kind, review.source_key},
       %{state: review.decision, reviewed_at: DateTime.to_iso8601(review.reviewed_at)}}
    end)
  end

  defp validate_input(kind, source_key, decision) do
    cond do
      kind not in @kinds -> {:error, :invalid_draft_kind}
      not is_binary(source_key) or String.trim(source_key) == "" -> {:error, :invalid_source_key}
      decision not in @decisions -> {:error, :invalid_review_decision}
      true -> :ok
    end
  end

  defp validate_source(repo, "image", source_key) do
    case repo.get(ImageDraft, source_key) do
      nil -> {:error, :not_found}
      %ImageDraft{state: "published"} -> {:error, :already_published}
      %ImageDraft{} -> :ok
    end
  end

  defp validate_source(repo, kind, source_key) when kind in ["text", "like"] do
    case repo.get(InteractionEvent, source_key) do
      nil ->
        {:error, :not_found}

      %InteractionEvent{state: "completed", payload: payload} ->
        validate_event_source(kind, payload)

      %InteractionEvent{} ->
        {:error, :not_reviewable}
    end
  end

  defp validate_event_source(kind, payload) do
    action = value(payload, "action")
    cycle_status = value(payload, "cycle_status")

    cond do
      cycle_status != "simulated" -> {:error, :not_reviewable}
      kind == "like" and action == "like" -> :ok
      kind == "text" and action in @text_actions -> :ok
      true -> {:error, :draft_kind_mismatch}
    end
  end

  defp review_key(kind, source_key) do
    digest = :crypto.hash(:sha256, source_key) |> Base.url_encode64(padding: false)
    "#{kind}:#{digest}"
  end

  defp value(map, "action"), do: Map.get(map || %{}, "action", Map.get(map || %{}, :action))

  defp value(map, "cycle_status"),
    do: Map.get(map || %{}, "cycle_status", Map.get(map || %{}, :cycle_status))
end
