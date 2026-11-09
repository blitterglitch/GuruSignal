defmodule GuruSignal.Monitoring.IPPolicyTest do
  use ExUnit.Case, async: true
  alias GuruSignal.Monitoring.IPPolicy

  defp ip(text), do: text |> String.to_charlist() |> :inet.parse_address() |> elem(1)

  test "blocks private, special-use, metadata, multicast, and reserved IPv4 destinations" do
    for text <- [
          "0.0.0.0",
          "0.255.255.255",
          "10.0.0.0",
          "10.255.255.255",
          "100.64.0.0",
          "100.127.255.255",
          "127.0.0.1",
          "169.254.169.254",
          "172.16.0.0",
          "172.31.255.255",
          "192.0.0.9",
          "192.0.2.1",
          "192.31.196.1",
          "192.52.193.1",
          "192.88.99.1",
          "192.168.1.1",
          "192.175.48.1",
          "198.18.0.1",
          "198.19.255.255",
          "198.51.100.1",
          "203.0.113.1",
          "224.0.0.1",
          "239.255.255.255",
          "240.0.0.1",
          "255.255.255.255",
          "168.63.129.16"
        ] do
      refute IPPolicy.public?(ip(text)), "allowed #{text}"
    end
  end

  test "permits public IPv4 addresses immediately outside blocked ranges" do
    for text <- [
          "1.1.1.1",
          "8.8.8.8",
          "100.63.255.255",
          "100.128.0.0",
          "126.255.255.255",
          "128.0.0.0",
          "172.15.255.255",
          "172.32.0.0",
          "192.167.255.255",
          "192.169.0.0",
          "198.17.255.255",
          "198.20.0.0",
          "223.255.255.255"
        ] do
      assert IPPolicy.public?(ip(text)), "blocked #{text}"
    end
  end

  test "blocks IPv6 private, transition, mapped, documentation, and special-use addresses" do
    for text <- [
          "::",
          "::1",
          "::127.0.0.1",
          "::ffff:127.0.0.1",
          "::ffff:8.8.8.8",
          "64:ff9b::a00:1",
          "64:ff9b:1::1",
          "100::1",
          "2001::1",
          "2001:1::1",
          "2001:2::1",
          "2001:db8::1",
          "2002:7f00:1::",
          "2620:4f:8000::1",
          "3fff::1",
          "5f00::1",
          "fc00::1",
          "fdaa::1",
          "fe80::1",
          "ff02::1"
        ] do
      refute IPPolicy.public?(ip(text)), "allowed #{text}"
    end

    for text <- ["2001:4860:4860::8888", "2606:4700:4700::1111", "2a09:8280::1"] do
      assert IPPolicy.public?(ip(text))
    end
  end

  test "malformed addresses fail closed" do
    for address <- [
          nil,
          "8.8.8.8",
          {8, 8, 8},
          {256, 1, 1, 1},
          {-1, 1, 1, 1},
          {0x2000, 0, 0, 0, 0, 0, 0, 65_536}
        ] do
      refute IPPolicy.public?(address)
    end
  end
end
