defmodule GuruSignalWeb.SessionController do
  use GuruSignalWeb, :controller

  alias GuruSignal.OwnerAccess

  plug(:prevent_caching)

  def new(conn, _params), do: render(conn, :new, error: nil)

  def create(conn, params) do
    case OwnerAccess.authenticate(params["password"]) do
      {:ok, token} ->
        OwnerAccess.revoke(get_session(conn, :owner_token))

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:owner_token, token)
        |> put_session(:live_socket_id, OwnerAccess.socket_id(token))
        |> redirect(to: ~p"/admin")

      {:error, :rate_limited} ->
        conn
        |> put_resp_header("retry-after", "60")
        |> put_status(:too_many_requests)
        |> render(:new, error: "Too many attempts. Try again in one minute.")

      {:error, :unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> render(:new, error: "Owner login is not configured.")

      {:error, :invalid} ->
        conn
        |> put_status(:unauthorized)
        |> render(:new, error: "Invalid password.")
    end
  end

  def delete(conn, _params) do
    OwnerAccess.revoke(get_session(conn, :owner_token))

    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> redirect(to: ~p"/login")
  end

  defp prevent_caching(conn, _opts), do: put_resp_header(conn, "cache-control", "no-store")
end
