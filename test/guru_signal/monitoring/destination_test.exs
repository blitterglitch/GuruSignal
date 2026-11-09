defmodule GuruSignal.Monitoring.DestinationTest do
  use ExUnit.Case, async: true
  alias GuruSignal.Monitoring.Destination

  defmodule Resolver do
    def resolve(host) do
      send(self(), {:resolved, host})
      Process.get(:dns_result, {:ok, [{8, 8, 8, 8}]})
    end
  end

  test "pins an authorized address and revalidates DNS on every check" do
    assert {:ok, target} = Destination.resolve("https://service.example.org/health", Resolver)
    assert target.address == {8, 8, 8, 8}
    assert target.uri.host == "service.example.org"
    assert_received {:resolved, "service.example.org"}
    refute_received {:resolved, _}
    Process.put(:dns_result, {:ok, [{127, 0, 0, 1}]})

    assert {:error, :blocked_destination} =
             Destination.resolve("https://service.example.org/health", Resolver)
  end

  test "a mixed public and private DNS answer rejects the entire destination" do
    Process.put(:dns_result, {:ok, [{8, 8, 8, 8}, {0xFD00, 0, 0, 0, 0, 0, 0, 1}]})

    assert {:error, :blocked_destination} =
             Destination.resolve("https://service.example.org", Resolver)
  end

  test "local/private names and IP literals cannot reach the resolver" do
    for url <- [
          "http://localhost",
          "http://LOCALHOST.",
          "http://app.internal",
          "http://metadata.google.internal",
          "http://printer.local",
          "http://router.home.arpa",
          "http://singlelabel",
          "http://127.1",
          "http://2130706433",
          "http://169.254.169.254",
          "http://[::ffff:127.0.0.1]",
          "http://[fdaa::1]"
        ] do
      assert {:error, :blocked_destination} = Destination.resolve(url, Resolver), url
    end

    refute_received {:resolved, _}
  end

  test "DNS errors, empty answers, and oversized answer sets fail closed" do
    for response <- [{:error, :nxdomain}, {:ok, []}, {:ok, List.duplicate({8, 8, 8, 8}, 33)}] do
      Process.put(:dns_result, response)
      assert {:error, _} = Destination.resolve("https://service.example.org", Resolver)
    end
  end
end
