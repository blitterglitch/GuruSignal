defmodule GuruSignalWeb.OwnerAuth do
  @moduledoc "HTTP and LiveView authentication for the single owner."
  use GuruSignalWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias GuruSignal.OwnerAccess

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    if OwnerAccess.remaining(get_session(conn, :owner_token)) > 0 do
      conn
    else
      conn |> redirect(to: ~p"/login") |> halt()
    end
  end

  def on_mount(:require_owner, _params, session, socket) do
    token = session["owner_token"]
    remaining = OwnerAccess.remaining(token)

    if remaining > 0 do
      if Phoenix.LiveView.connected?(socket) do
        Process.send_after(self(), :owner_session_expired, remaining)
      end

      socket =
        socket
        |> Phoenix.Component.assign(:owner_token, token)
        |> Phoenix.LiveView.attach_hook(:owner_authorization, :handle_event, fn _, _, socket ->
          if OwnerAccess.remaining(socket.assigns.owner_token) > 0 do
            {:cont, socket}
          else
            {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
          end
        end)
        |> Phoenix.LiveView.attach_hook(:owner_expiry, :handle_info, fn
          :owner_session_expired, socket ->
            {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}

          _message, socket ->
            {:cont, socket}
        end)

      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end
end
