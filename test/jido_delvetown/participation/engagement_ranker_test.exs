defmodule JidoDelvetown.EngagementRankerTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.EngagementRanker

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

    rank =
      EngagementRanker.score(candidate, :direct, state(1, 0),
        now: now,
        limits: limits()
      )

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

    first = EngagementRanker.best([older, recent], :direct, state(), now: now, limits: limits())
    second = EngagementRanker.best([recent, older], :direct, state(), now: now, limits: limits())

    assert first.id == "notification:a"
    assert second.id == first.id
    assert second.engagement_rank == first.engagement_rank
  end

  test "uses stable identity to resolve an exact score tie" do
    now = ~U[2026-10-05 12:00:00Z]
    a = candidate("notification:a", "2026-10-05T11:00:00Z", "OTP")
    b = candidate("notification:b", "2026-10-05T11:00:00Z", "OTP")

    assert EngagementRanker.best([b, a], :direct, state(), now: now, limits: limits()).id ==
             "notification:a"

    assert EngagementRanker.best([a, b], :direct, state(), now: now, limits: limits()).id ==
             "notification:a"
  end

  test "keeps opportunity priorities explicit" do
    candidate = candidate("event", "2026-10-05T11:00:00Z", "OTP")
    now = ~U[2026-10-05 12:00:00Z]

    direct = EngagementRanker.score(candidate, :direct, state(), now: now, limits: limits())
    follow = EngagementRanker.score(candidate, :follow, state(), now: now, limits: limits())
    member = EngagementRanker.score(candidate, :new_member, state(), now: now, limits: limits())

    discussion =
      EngagementRanker.score(candidate, :useful_discussion, state(),
        now: now,
        limits: limits()
      )

    post = EngagementRanker.score(candidate, :original_post, state(), now: now, limits: limits())

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
    %{budget: %{replies: replies, posts: posts, welcomes: 0, follows: 0}}
  end

  defp limits do
    %{
      daily_reply_limit: 3,
      daily_welcome_limit: 2,
      daily_post_limit: 1,
      daily_follow_limit: 5
    }
  end
end
