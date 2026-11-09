defmodule GuruSignalWeb.HealthController do
  use GuruSignalWeb, :controller
  alias GuruSignal.Health

  plug :prevent_caching

  def live(conn, _params), do: json(conn, %{status: "ok"})

  def ready(conn, _params) do
    if Health.ready?() do
      json(conn, %{status: "ok"})
    else
      conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
    end
  end

  defp prevent_caching(conn, _opts), do: put_resp_header(conn, "cache-control", "no-store")
end
