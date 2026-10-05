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
    note = CreativeFormats.prepare(cycle([], "publish_daily_note"))

    assert follow.response_format.id == "protocol_field_note"
    assert note.response_format.id == "short_build_log"
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
