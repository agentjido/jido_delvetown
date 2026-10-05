defmodule JidoDelvetown.OptOut do
  @moduledoc false

  @phrases [
    "do not contact me",
    "do not reply",
    "don't contact me",
    "don't reply",
    "leave me alone",
    "opt out",
    "stop contacting me",
    "stop replying"
  ]

  def requested?(text) when is_binary(text) do
    normalized = String.downcase(text)
    Enum.any?(@phrases, &String.contains?(normalized, &1))
  end

  def requested?(_text), do: false
end
