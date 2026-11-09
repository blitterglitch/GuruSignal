defmodule GuruSignal.Monitoring.IPPolicy do
  @moduledoc "Conservative public-address policy, reviewed against IANA on 2026-11-09."
  import Bitwise

  # Entire special-use ranges are blocked, including their globally reachable exceptions.
  @ipv4_blocked [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 0, 0, 0}, 24},
    {{192, 0, 2, 0}, 24},
    {{192, 31, 196, 0}, 24},
    {{192, 52, 193, 0}, 24},
    {{192, 88, 99, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{192, 175, 48, 0}, 24},
    {{198, 18, 0, 0}, 15},
    {{198, 51, 100, 0}, 24},
    {{203, 0, 113, 0}, 24},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4},
    # Azure platform virtual address, in addition to ordinary metadata/link-local blocks.
    {{168, 63, 129, 16}, 32}
  ]
  @ipv6_blocked [
    {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 23},
    {{0x2001, 0xDB8, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2002, 0, 0, 0, 0, 0, 0, 0}, 16},
    {{0x2620, 0x4F, 0x8000, 0, 0, 0, 0, 0}, 48},
    {{0x3FFF, 0, 0, 0, 0, 0, 0, 0}, 20}
  ]

  def public?(address) when is_tuple(address) and tuple_size(address) == 4 do
    valid_parts?(address, 255) and not Enum.any?(@ipv4_blocked, &member?(address, &1, 8))
  end

  def public?(address) when is_tuple(address) and tuple_size(address) == 8 do
    valid_parts?(address, 65_535) and
      member?(address, {{0x2000, 0, 0, 0, 0, 0, 0, 0}, 3}, 16) and
      not Enum.any?(@ipv6_blocked, &member?(address, &1, 16))
  end

  def public?(_address), do: false

  defp valid_parts?(address, maximum) do
    address |> Tuple.to_list() |> Enum.all?(&(is_integer(&1) and &1 >= 0 and &1 <= maximum))
  end

  defp member?(address, {network, prefix}, part_bits) do
    shift = tuple_size(address) * part_bits - prefix
    bsr(integer(address, part_bits), shift) == bsr(integer(network, part_bits), shift)
  end

  defp integer(address, part_bits) do
    address |> Tuple.to_list() |> Enum.reduce(0, fn part, acc -> bsl(acc, part_bits) + part end)
  end
end
