defmodule JidoDelvetown.Test.FakeDecision do
  @moduledoc false

  def choose(intent, payload, _context) do
    if owner = Application.get_env(:jido_delvetown, :test_owner) do
      send(owner, {:decision, intent, payload})
    end

    Application.get_env(
      :jido_delvetown,
      :decision_result,
      {:ok, %{action: "skip", text: nil, topic: nil, reason: "test skip"}}
    )
  end
end
