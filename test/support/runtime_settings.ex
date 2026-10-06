defmodule JidoDelvetown.Test.RuntimeSettings do
  @moduledoc false

  alias JidoDelvetown.Settings

  def preserve!(changes) when is_map(changes) or is_list(changes) do
    changes = Map.new(changes)
    {:ok, current} = Settings.current()
    original = Map.take(current.values, Map.keys(changes))
    update!(changes)

    fn -> update!(original) end
  end

  def update!(changes) when is_map(changes) or is_list(changes) do
    changes = Map.new(changes)

    {:ok, settings} =
      Settings.update(changes,
        source: "test",
        confirmed: Map.keys(changes)
      )

    settings
  end
end
