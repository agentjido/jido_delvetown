defmodule JidoDelvetown.TidTest do
  use ExUnit.Case, async: true

  alias JidoDelvetown.Tid

  test "TIDs use the AT Protocol alphabet and increase" do
    first = Tid.generate()
    second = Tid.generate()

    assert String.length(first) == 13
    assert first =~ ~r/\A[234567abcdefghijklmnopqrstuvwxyz]{13}\z/
    assert first < second
  end
end
