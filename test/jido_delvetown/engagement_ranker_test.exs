defmodule JidoDelvetown.EngagementRankerTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.EngagementRanker

  setup do
    old_limit = System.get_env("DELVETOWN_DAILY_REPLY_LIMIT")
    System.put_env("DELVETOWN_DAILY_REPLY_LIMIT", "3")

    on_exit(fn ->
      if old_limit,
        do: System.put_env("DELVETOWN_DAILY_REPLY_LIMIT", old_limit),
        else: System.delete_env("DELVETOWN_DAILY_REPLY_LIMIT")
    end)

    :ok
  end

  test "reports every policy factor" do
    now = ~U[2026-10-05 12:00:00Z]

    candidate = %{
      id: "reply-1",
      event_key: "notification:reply-1",
      reason: "reply",
      indexed_at: "2026-10-05T11:00:00Z",
      text: "How should an OTP supervisor own this failure?",
      memory: %{
        actor: %{contact_count: 1},
        conversation: %{turn_count: 2}
      }
    }

    rank = EngagementRanker.score(candidate, :direct, state(1, 0), now: now)

    assert rank.factors == %{
             priority: 100,
             recency: 19,
             relevance: 15,
             prior_contact: 2,
             conversation_load: 0,
             budget: 2
           }

    assert rank.score == 138
    assert rank.reason =~ "direct scored 138"
  end

  test "selects the same candidate when input order changes" do
    now = ~U[2026-10-05 12:00:00Z]

    older = candidate("notification:b", "2026-10-05T08:00:00Z", "A general note")

    recent =
      candidate(
        "notification:a",
        "2026-10-05T11:30:00Z",
        "An OTP agent protocol failure question"
      )

    first = EngagementRanker.best([older, recent], :direct, state(), now: now)
    second = EngagementRanker.best([recent, older], :direct, state(), now: now)

    assert first.id == "notification:a"
    assert second.id == first.id
    assert second.engagement_rank == first.engagement_rank
  end

  test "uses stable identity to resolve an exact score tie" do
    now = ~U[2026-10-05 12:00:00Z]
    a = candidate("notification:a", "2026-10-05T11:00:00Z", "OTP")
    b = candidate("notification:b", "2026-10-05T11:00:00Z", "OTP")

    assert EngagementRanker.best([b, a], :direct, state(), now: now).id == "notification:a"
    assert EngagementRanker.best([a, b], :direct, state(), now: now).id == "notification:a"
  end

  test "keeps opportunity priorities explicit" do
    candidate = candidate("event", "2026-10-05T11:00:00Z", "OTP")
    now = ~U[2026-10-05 12:00:00Z]

    direct = EngagementRanker.score(candidate, :direct, state(), now: now)
    follow = EngagementRanker.score(candidate, :follow, state(), now: now)
    member = EngagementRanker.score(candidate, :new_member, state(), now: now)
    discussion = EngagementRanker.score(candidate, :useful_discussion, state(), now: now)
    post = EngagementRanker.score(candidate, :original_post, state(), now: now)

    assert direct.score > follow.score
    assert follow.score > member.score
    assert member.score > discussion.score
    assert discussion.score > post.score
  end

  defp candidate(id, indexed_at, text) do
    %{
      id: id,
      event_key: id,
      reason: "reply",
      indexed_at: indexed_at,
      text: text,
      memory: %{actor: nil, conversation: nil}
    }
  end

  defp state(replies \\ 0, posts \\ 0) do
    %{budget: %{replies: replies, posts: posts}}
  end
end
