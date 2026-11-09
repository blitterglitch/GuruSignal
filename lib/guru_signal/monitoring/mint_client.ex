defmodule GuruSignal.Monitoring.MintClient do
  @moduledoc "A fresh, pinned-IP HTTP/1 connection, closed after final response headers."
  alias GuruSignal.Monitoring.HTTPResponse

  def fetch(target, deadline, opts \\ []) do
    http = Keyword.get(opts, :http, Mint.HTTP)
    uri = target.uri
    scheme = if uri.scheme == "https", do: :https, else: :http

    transport = [
      timeout: remaining(deadline),
      inet6: tuple_size(target.address) == 8,
      inet4: tuple_size(target.address) == 4,
      buffer: 8_192,
      recbuf: 8_192,
      send_timeout: remaining(deadline),
      send_timeout_close: true
    ]

    transport =
      if scheme == :https do
        transport ++
          [
            verify: :verify_peer,
            cacerts: Keyword.get_lazy(opts, :cacerts, &:public_key.cacerts_get/0),
            versions: [:"tlsv1.2", :"tlsv1.3"]
          ]
      else
        transport
      end

    connection_opts = [
      hostname: uri.host,
      mode: :passive,
      protocols: [:http1],
      max_header_list_size: 16_384,
      transport_opts: transport,
      log: false
    ]

    # No hostname is given to the socket connector: DNS has already been validated.
    case http.connect(scheme, target.address, uri.port, connection_opts) do
      {:ok, connection} ->
        try do
          path = if uri.path in [nil, ""], do: "/", else: uri.path
          path = if uri.query, do: path <> "?" <> uri.query, else: path

          case http.request(
                 connection,
                 "GET",
                 path,
                 [{"user-agent", "GuruSignal/0.1"}, {"connection", "close"}],
                 nil
               ) do
            {:ok, connection, reference} ->
              receive_headers(http, connection, reference, deadline, %HTTPResponse{})

            {:error, _connection, error} ->
              {:error, category(error)}
          end
        after
          http.close(connection)
        end

      {:error, error} ->
        {:error, category(error)}
    end
  end

  defp receive_headers(http, connection, reference, deadline, state) do
    if remaining(deadline) == 0 do
      {:error, :timeout}
    else
      case http.recv(connection, 0, remaining(deadline)) do
        {:ok, connection, responses} ->
          process_responses(http, connection, reference, deadline, state, responses, nil)

        {:error, connection, error, responses} ->
          process_responses(http, connection, reference, deadline, state, responses, error)
      end
    end
  end

  defp process_responses(http, connection, reference, deadline, state, responses, error) do
    case HTTPResponse.consume(state, responses, reference) do
      {:error, reason} ->
        {:error, reason}

      {:ok, %{complete?: true, status: status}} ->
        {:ok, status}

      {:ok, state} when is_nil(error) ->
        receive_headers(http, connection, reference, deadline, state)

      {:ok, _state} ->
        {:error, category(error)}
    end
  end

  defp category(%{reason: :timeout}), do: :timeout
  defp category(%{reason: {:tls_alert, _}}), do: :tls
  defp category(%{reason: {:options, _}}), do: :tls
  defp category(%{reason: {:max_header_list_size_exceeded, _, _}}), do: :response_limit
  defp category(%{reason: {:response_line_too_long, _, _}}), do: :response_limit
  defp category(%{__struct__: Mint.HTTPError}), do: :protocol
  defp category(_error), do: :connection

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
