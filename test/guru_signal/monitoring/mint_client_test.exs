defmodule GuruSignal.Monitoring.MintClientTest do
  use ExUnit.Case, async: true
  alias GuruSignal.Monitoring.MintClient

  defmodule HTTP do
    def connect(scheme, address, port, opts) do
      send(self(), {:connect, scheme, address, port, opts})
      {:ok, %{address: address, round: 0}}
    end

    def request(conn, method, path, headers, body) do
      send(self(), {:request, method, path, headers, body})
      ref = make_ref()
      {:ok, Map.merge(conn, %{ref: ref, path: path}), ref}
    end

    def recv(%{path: "/timeout"} = conn, _bytes, _timeout),
      do: {:error, conn, %{reason: :timeout}, []}

    def recv(%{path: "/large"} = conn, _bytes, _timeout),
      do: {:error, conn, %{reason: {:max_header_list_size_exceeded, 20_000, 16_384}}, []}

    def recv(%{path: "/interim", round: 0} = conn, _bytes, _timeout) do
      {:ok, %{conn | round: 1}, [{:status, conn.ref, 100}, {:headers, conn.ref, []}]}
    end

    def recv(conn, _bytes, _timeout) do
      status = if conn.path == "/redirect", do: 302, else: 200

      {:ok, conn,
       [{:status, conn.ref, status}, {:headers, conn.ref, [{"location", "http://127.0.0.1"}]}]}
    end

    def close(conn) do
      send(self(), {:closed, conn.address})
      {:ok, conn}
    end
  end

  defp target(path) do
    %{
      uri: URI.new!("https://service.example.org" <> path),
      address: {0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111}
    }
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 1_000

  test "connects only to the pinned IP with original TLS identity and bounded options" do
    target = target("/health?key=value")
    assert {:ok, 200} = MintClient.fetch(target, deadline(), http: HTTP, cacerts: [])
    assert_received {:connect, :https, address, 443, opts}
    assert address == target.address
    assert opts[:hostname] == "service.example.org"
    assert opts[:mode] == :passive and opts[:protocols] == [:http1]
    assert opts[:max_header_list_size] == 16_384
    assert opts[:transport_opts][:verify] == :verify_peer
    assert opts[:transport_opts][:inet6] and not opts[:transport_opts][:inet4]
    refute Keyword.has_key?(opts, :proxy)
    assert_received {:request, "GET", "/health?key=value", _headers, nil}
    assert_received {:closed, ^address}
  end

  test "returns a redirect status without connecting to its Location" do
    assert {:ok, 302} = MintClient.fetch(target("/redirect"), deadline(), http: HTTP, cacerts: [])
    assert_received {:connect, _, _, _, _}
    refute_received {:connect, _, _, _, _}
  end

  test "waits for final headers and closes connections on errors" do
    assert {:ok, 200} = MintClient.fetch(target("/interim"), deadline(), http: HTTP, cacerts: [])
    assert_received {:closed, _}

    assert {:error, :timeout} =
             MintClient.fetch(target("/timeout"), deadline(), http: HTTP, cacerts: [])

    assert_received {:closed, _}

    assert {:error, :response_limit} =
             MintClient.fetch(target("/large"), deadline(), http: HTTP, cacerts: [])

    assert_received {:closed, _}
  end
end
