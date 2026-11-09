defmodule GuruSignalWeb.HealthSSLTest do
  use ExUnit.Case, async: true

  test "production permits HTTP probes and redirects regular public-host traffic to HTTPS" do
    config = Config.Reader.read!(Path.expand("../../config/prod.exs", __DIR__))
    opts = config[:guru_signal][GuruSignalWeb.Endpoint][:force_ssl] |> Plug.SSL.init()

    for path <- ["/health/live", "/health/ready"] do
      response = request(path) |> Plug.SSL.call(opts)
      refute response.halted
      assert response.scheme == :http
    end

    response = request("/login") |> Plug.SSL.call(opts)
    assert response.halted
    assert response.status == 301
    assert Plug.Conn.get_resp_header(response, "location") == ["https://status.example.com/login"]
  end

  defp request(path), do: %{Plug.Test.conn(:get, path) | host: "status.example.com"}
end
