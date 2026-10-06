defmodule JidoDelvetown.Tid do
  @moduledoc "Generates sortable AT Protocol transaction identifiers."

  import Bitwise

  @alphabet "234567abcdefghijklmnopqrstuvwxyz"
  @length 13
  @clock_mask 0x3FF

  def generate do
    clock_id = System.unique_integer([:monotonic, :positive]) &&& @clock_mask
    integer = System.system_time(:microsecond) <<< 10 ||| clock_id
    encode(integer, @length, [])
  end

  defp encode(_integer, 0, acc), do: IO.iodata_to_binary(acc)

  defp encode(integer, remaining, acc) do
    index = integer &&& 0x1F
    character = binary_part(@alphabet, index, 1)
    encode(integer >>> 5, remaining - 1, [character | acc])
  end
end
