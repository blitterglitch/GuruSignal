defmodule GuruSignalWeb.SessionControllerTest do
  use GuruSignalWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "owner login protects HTTP and LiveView access and logout revokes the session", %{
    conn: conn
  } do
    previous = Application.get_env(:guru_signal, :owner_password_hash)
    hash = Pbkdf2.hash_pwd_salt("integration-test-password", rounds: 1)
    Application.put_env(:guru_signal, :owner_password_hash, hash)
    on_exit(fn -> Application.put_env(:guru_signal, :owner_password_hash, previous) end)

    assert redirected_to(get(conn, ~p"/admin")) == ~p"/login"
    assert html_response(get(conn, ~p"/login"), 200) =~ "Owner password"

    invalid = post(conn, ~p"/login", %{"password" => "wrong"})
    assert html_response(invalid, 401) =~ "Invalid password"

    signed_in = post(conn, ~p"/login", %{"password" => "integration-test-password"})
    assert redirected_to(signed_in) == ~p"/admin"
    token = get_session(signed_in, :owner_token)
    assert GuruSignal.OwnerAccess.remaining(token) > 0

    authenticated = recycle(signed_in)
    assert {:ok, view, html} = live(authenticated, ~p"/admin")
    assert html =~ "GuruSignal administration"
    assert render(view) =~ "Sign out"

    signed_out = delete(authenticated, ~p"/logout")
    assert redirected_to(signed_out) == ~p"/login"
    assert GuruSignal.OwnerAccess.remaining(token) == 0
    assert redirected_to(get(recycle(signed_out), ~p"/admin")) == ~p"/login"

    # Even a still-present signed cookie cannot revive a revoked server session.
    assert redirected_to(get(recycle(signed_in), ~p"/admin")) == ~p"/login"
  end

  test "LiveView mount independently rejects missing owner sessions" do
    socket = %Phoenix.LiveView.Socket{endpoint: GuruSignalWeb.Endpoint}
    assert {:halt, socket} = GuruSignalWeb.OwnerAuth.on_mount(:require_owner, %{}, %{}, socket)
    assert socket.redirected == {:redirect, %{to: "/login", status: 302}}
  end

  test "login fails closed without owner configuration", %{conn: conn} do
    previous = Application.get_env(:guru_signal, :owner_password_hash)
    Application.delete_env(:guru_signal, :owner_password_hash)
    on_exit(fn -> Application.put_env(:guru_signal, :owner_password_hash, previous) end)

    response = post(conn, ~p"/login", %{"password" => "anything"})
    assert html_response(response, 503) =~ "Owner login is not configured"
  end
end
