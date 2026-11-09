defmodule GuruSignal.Monitoring.EndpointTest do
  use ExUnit.Case, async: true

  alias GuruSignal.Monitoring.Endpoint

  defp changeset(attrs),
    do:
      Endpoint.changeset(
        %Endpoint{},
        Map.merge(%{name: "Homepage", url: "https://example.com"}, attrs)
      )

  test "trims names and URLs and supplies sensible defaults" do
    result = changeset(%{name: "  Homepage  ", url: " https://example.com/health "})
    assert result.valid?
    endpoint = Ecto.Changeset.apply_changes(result)
    assert endpoint.name == "Homepage"
    assert endpoint.url == "https://example.com/health"
    assert endpoint.expected_status == 200
    assert endpoint.interval_seconds == 60
    assert endpoint.timeout_ms == 5_000
    assert endpoint.enabled
  end

  test "requires a bounded name and URL" do
    refute changeset(%{name: "   "}).valid?
    refute changeset(%{name: String.duplicate("x", 101)}).valid?
    refute changeset(%{url: ""}).valid?
    refute changeset(%{url: "https://example.com/" <> String.duplicate("x", 2048)}).valid?
  end

  test "validates all supported numeric boundaries and accepts disabled endpoints" do
    for status <- [200, 599], interval <- [60, 300, 900], timeout <- [1_000, 10_000] do
      assert changeset(%{
               expected_status: status,
               interval_seconds: interval,
               timeout_ms: timeout,
               enabled: false
             }).valid?
    end

    for attrs <- [
          %{expected_status: 199},
          %{expected_status: 600},
          %{interval_seconds: 30},
          %{timeout_ms: 999},
          %{timeout_ms: 10_001},
          %{enabled: "maybe"}
        ] do
      refute changeset(attrs).valid?
    end
  end

  test "rejects unsupported or ambiguous URLs without resolving DNS" do
    for url <- [
          "example.com",
          "ftp://example.com",
          "//example.com",
          "https:///path",
          "https://user:secret@example.com",
          "https://example.com/#fragment",
          "https://example.com:8443",
          "http://example.com:443",
          "https://bad_host.example",
          "https://example.com..",
          "https://example.com/path with spaces",
          "https://example.com/\\path",
          "https://example.com/\0"
        ] do
      result = changeset(%{url: url})
      refute result.valid?, "accepted #{inspect(url)}"
      assert Keyword.has_key?(result.errors, :url)
    end
  end

  test "accepts standard ports, escaped paths, query strings, and IPv6 syntax" do
    for url <- [
          "http://example.com:80/health",
          "https://example.com:443/a%20b?key=value",
          "https://[2606:4700:4700::1111]/"
        ] do
      assert changeset(%{url: url}).valid?
    end
  end

  test "owner input cannot set the database identity or concurrency version" do
    result =
      changeset(%{
        id: 123,
        lock_version: 999,
        check_sequence: 999,
        last_check_sequence: 999,
        next_check_at: DateTime.utc_now()
      })
      |> Ecto.Changeset.apply_changes()

    assert result.id == nil
    assert result.lock_version == 1
    assert result.check_sequence == 0
    assert result.last_check_sequence == 0
    assert result.next_check_at == nil
  end
end
