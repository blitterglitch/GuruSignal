defmodule GuruSignal.Monitoring.MintClientSocketTest do
  use ExUnit.Case, async: true
  alias GuruSignal.Monitoring.MintClient

  setup_all do
    Application.ensure_all_started(:ssl)

    directory =
      Path.join(System.tmp_dir!(), "guru-signal-tls-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    on_exit(fn -> File.rm_rf!(directory) end)
    key = Path.join(directory, "key.pem")
    cert = Path.join(directory, "cert.pem")
    ca_key = Path.join(directory, "ca-key.pem")
    ca_cert = Path.join(directory, "ca-cert.pem")
    csr = Path.join(directory, "server.csr")
    extensions = Path.join(directory, "server.ext")

    openssl!([
      "req",
      "-x509",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-keyout",
      ca_key,
      "-out",
      ca_cert,
      "-days",
      "1",
      "-subj",
      "/CN=GuruSignal Test CA",
      "-addext",
      "basicConstraints=critical,CA:TRUE",
      "-addext",
      "keyUsage=critical,keyCertSign,cRLSign"
    ])

    openssl!([
      "req",
      "-new",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-keyout",
      key,
      "-out",
      csr,
      "-subj",
      "/CN=service.example.org"
    ])

    File.write!(extensions, """
    basicConstraints=critical,CA:FALSE
    keyUsage=critical,digitalSignature,keyEncipherment
    extendedKeyUsage=serverAuth
    subjectAltName=DNS:service.example.org
    """)

    openssl!([
      "x509",
      "-req",
      "-in",
      csr,
      "-CA",
      ca_cert,
      "-CAkey",
      ca_key,
      "-CAcreateserial",
      "-out",
      cert,
      "-days",
      "1",
      "-sha256",
      "-extfile",
      extensions
    ])

    openssl!(["verify", "-CAfile", ca_cert, "-verify_hostname", "service.example.org", cert])

    [{:Certificate, der, _}] = ca_cert |> File.read!() |> :public_key.pem_decode()

    {:ok,
     certificate: der,
     tls_options: [certfile: String.to_charlist(cert), keyfile: String.to_charlist(key)]}
  end

  defp openssl!(arguments) do
    {output, status} = System.cmd("openssl", arguments, stderr_to_stdout: true)
    assert status == 0, "TLS fixture certificate generation failed: #{output}"
  end

  defmodule DiagnosticHTTP do
    def connect(scheme, address, port, opts) do
      result = Mint.HTTP.connect(scheme, address, port, opts)

      case result do
        {:error, error} -> send(self(), {:fixture_tls_error, error})
        _ -> :ok
      end

      result
    end

    defdelegate request(conn, method, path, headers, body), to: Mint.HTTP
    defdelegate recv(conn, bytes, timeout), to: Mint.HTTP
    defdelegate close(conn), to: Mint.HTTP
  end

  defp fixture(response, opts \\ []) do
    transport = if opts[:tls_options], do: :ssl, else: :gen_tcp

    {:ok, listener} =
      transport.listen(
        0,
        [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}] ++
          Keyword.get(opts, :tls_options, [])
      )

    {:ok, {_address, port}} =
      if transport == :ssl, do: :ssl.sockname(listener), else: :inet.sockname(listener)

    parent = self()

    pid =
      spawn(fn ->
        accepted =
          if transport == :ssl do
            with {:ok, socket} <- :ssl.transport_accept(listener, 3000),
                 do: :ssl.handshake(socket, 3000)
          else
            :gen_tcp.accept(listener, 3000)
          end

        case accepted do
          {:ok, socket} ->
            request = read_request(transport, socket, "")
            send(parent, {:fixture_request, request})
            transport.send(socket, response)

            if opts[:wait_for_close],
              do: send(parent, {:fixture_closed, transport.recv(socket, 0, 3000)})

            transport.close(socket)

          {:error, _} ->
            :ok
        end
      end)

    on_exit(fn ->
      Process.exit(pid, :kill)
      transport.close(listener)
    end)

    scheme = if transport == :ssl, do: "https", else: "http"

    %{
      address: {127, 0, 0, 1},
      uri: %URI{scheme: scheme, host: "service.example.org", port: port, path: "/health"}
    }
  end

  defp read_request(transport, socket, data) do
    if String.contains?(data, "\r\n\r\n") do
      data
    else
      {:ok, chunk} = transport.recv(socket, 0, 3000)
      read_request(transport, socket, data <> chunk)
    end
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 3000

  test "real HTTP uses the original Host and closes after headers without reading a promised body" do
    target = fixture("HTTP/1.1 200 OK\r\nContent-Length: 999999\r\n\r\n", wait_for_close: true)
    assert {:ok, 200} = MintClient.fetch(target, deadline())
    assert_receive {:fixture_request, request}, 1000
    assert request =~ "host: service.example.org:#{target.uri.port}"
    assert_receive {:fixture_closed, {:error, :closed}}, 1000
  end

  test "real HTTP does not follow a redirect to a private address" do
    target =
      fixture(
        "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1/secret\r\nContent-Length: 0\r\n\r\n"
      )

    assert {:ok, 302} = MintClient.fetch(target, deadline())
  end

  test "real parser rejects an oversized header section" do
    target =
      fixture("HTTP/1.1 200 OK\r\nX-Large: " <> String.duplicate("x", 20_000) <> "\r\n\r\n")

    assert {:error, :response_limit} = MintClient.fetch(target, deadline())
  end

  test "TLS checks the original hostname when connecting to a pinned IP", context do
    target = fixture("HTTP/1.1 204 No Content\r\n\r\n", tls_options: context.tls_options)

    result =
      MintClient.fetch(target, deadline(), cacerts: [context.certificate], http: DiagnosticHTTP)

    detail =
      receive do
        {:fixture_tls_error, error} -> inspect(error)
      after
        0 -> "no connection error"
      end

    assert result == {:ok, 204}, "TLS fixture returned #{inspect(result)}: #{detail}"
  end

  test "TLS rejects a certificate for a different hostname", context do
    target =
      fixture("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n", tls_options: context.tls_options)

    target = %{target | uri: %{target.uri | host: "wrong.example.org"}}
    assert {:error, :tls} = MintClient.fetch(target, deadline(), cacerts: [context.certificate])
  end

  test "TLS rejects a certificate signed by an untrusted CA", context do
    target = fixture("HTTP/1.1 204 No Content\r\n\r\n", tls_options: context.tls_options)
    assert {:error, :tls} = MintClient.fetch(target, deadline(), cacerts: [])
  end
end
