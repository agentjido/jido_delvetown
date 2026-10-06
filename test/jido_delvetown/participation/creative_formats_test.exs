defmodule JidoDelvetown.CreativeFormatsTest do
  use ExUnit.Case, async: true

  alias JidoDelvetown.CreativeFormats

  test "rotates formats against recent bounded history" do
    first = CreativeFormats.prepare(cycle([]))
    second = CreativeFormats.prepare(cycle([first.response_format.id]))

    third =
      CreativeFormats.prepare(cycle([second.response_format.id, first.response_format.id]))

    assert first.response_format.id == "state_machine_sketch"
    assert second.response_format.id == "protocol_field_note"
    assert third.response_format.id == "failure_mode_question"
    assert first.response_format.safety =~ "Accuracy"
  end

  test "uses intent-specific formats" do
    follow = CreativeFormats.prepare(cycle([], "respond_to_new_follow"))
    welcome = CreativeFormats.prepare(cycle([], "welcome_new_member"))
    note = CreativeFormats.prepare(cycle([], "publish_daily_note"))

    assert follow.response_format.id == "quiet_follow_response"
    assert welcome.response_format.id == "low_pressure_welcome"
    assert note.response_format.id == "short_build_log"
  end

  test "accepts a short welcome that refers to the introduction" do
    cycle = cycle([], "welcome_new_member") |> CreativeFormats.prepare()

    decision = %{
      action: "welcome",
      text: "Welcome to DelveTown; your OTP supervision note was clear.",
      topic: "OTP",
      reason: "Relevant introduction"
    }

    assert CreativeFormats.finalize(decision, cycle).action == "welcome"
  end

  test "rejects forceful or interactive welcome language" do
    cycle = cycle([], "welcome_new_member") |> CreativeFormats.prepare()

    forceful = %{
      action: "welcome",
      text: "Welcome to our community; feel free to explore our resources.",
      topic: "OTP",
      reason: "Generic welcome"
    }

    interactive = %{
      action: "welcome",
      text: "Welcome! What are you building with OTP?",
      topic: "OTP",
      reason: "Question"
    }

    assert CreativeFormats.finalize(forceful, cycle).reason ==
             "creative_format_validation_failed:welcome_too_forceful"

    assert CreativeFormats.finalize(interactive, cycle).reason ==
             "creative_format_validation_failed:welcome_call_to_action"
  end

  test "rejects a handle because the publisher adds the verified mention" do
    cycle = cycle([], "welcome_new_member") |> CreativeFormats.prepare()

    decision = %{
      action: "welcome",
      text: "Welcome, @new-member; your OTP note was clear.",
      topic: "OTP",
      reason: "Relevant introduction"
    }

    assert CreativeFormats.finalize(decision, cycle).reason ==
             "creative_format_validation_failed:welcome_includes_handle"
  end

  test "a generic opening falls back to silence" do
    cycle = cycle([]) |> CreativeFormats.prepare()

    decision = %{
      action: "reply",
      text: "Great point. I completely agree.",
      topic: "OTP",
      reason: "Friendly reply"
    }

    assert CreativeFormats.finalize(decision, cycle) == %{
             action: "skip",
             text: nil,
             topic: "OTP",
             reason: "creative_format_validation_failed:generic_opening",
             format: "validation_fallback"
           }
  end

  test "allows two uses and rejects the third repeated opening or topic" do
    state = %{
      voice: %{
        recent_formats: [],
        recent_openings: ["one process owns this", "one process owns this"],
        recent_topics: ["OTP", "OTP"]
      }
    }

    assert {:error, :repeated_opening} =
             CreativeFormats.validate(
               %{
                 action: "reply",
                 text: "One process owns this boundary because failures must have an owner.",
                 topic: "new topic"
               },
               state
             )

    assert {:error, :repeated_topic} =
             CreativeFormats.validate(
               %{
                 action: "reply",
                 text: "A supervisor makes restart ownership visible.",
                 topic: "OTP"
               },
               state
             )
  end

  defp cycle(recent_formats, intent \\ "answer_direct_request") do
    %{
      intent: intent,
      state: %{
        voice: %{
          recent_formats: recent_formats,
          recent_openings: [],
          recent_topics: []
        }
      }
    }
  end
end
