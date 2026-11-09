defmodule GuruSignalWeb.AdminLiveTest do
  use GuruSignalWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GuruSignal.MonitoringFixtures
  alias GuruSignal.Monitoring
  alias GuruSignal.OwnerAccess

  setup_all do
    previous = Application.get_env(:guru_signal, :owner_password_hash)

    Application.put_env(
      :guru_signal,
      :owner_password_hash,
      Pbkdf2.hash_pwd_salt("endpoint-test-password", rounds: 1)
    )

    result =
      try do
        OwnerAccess.authenticate("endpoint-test-password")
      after
        Application.put_env(:guru_signal, :owner_password_hash, previous)
      end

    {:ok, token} = result
    on_exit(fn -> OwnerAccess.revoke(token) end)
    {:ok, owner_token: token}
  end

  setup %{conn: conn, owner_token: token} do
    {:ok,
     conn:
       init_test_session(conn, %{owner_token: token, live_socket_id: OwnerAccess.socket_id(token)})}
  end

  test "owner can create, edit, pause, enable, and delete endpoints", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/admin")
    assert has_element?(view, "#empty-endpoints")

    view
    |> form("#endpoint-form", endpoint: %{name: "Homepage", url: "https://example.com/health"})
    |> render_submit()

    [endpoint] = Monitoring.list_endpoints()
    assert has_element?(view, "#endpoint-#{endpoint.id}", "Homepage")

    view |> element("#edit-endpoint-#{endpoint.id}") |> render_click()

    view
    |> form("#endpoint-form",
      endpoint: %{
        name: "API",
        expected_status: "204",
        interval_seconds: "300",
        timeout_ms: "1000"
      }
    )
    |> render_submit()

    updated = Monitoring.get_endpoint(endpoint.id)
    assert updated.name == "API"
    assert updated.expected_status == 204
    assert updated.interval_seconds == 300
    assert updated.timeout_ms == 1_000

    view |> element("#toggle-endpoint-#{endpoint.id}") |> render_click()
    refute Monitoring.get_endpoint(endpoint.id).enabled
    assert has_element?(view, "#endpoint-#{endpoint.id}", "Paused")
    view |> element("#toggle-endpoint-#{endpoint.id}") |> render_click()
    assert Monitoring.get_endpoint(endpoint.id).enabled

    view |> element("#delete-endpoint-#{endpoint.id}") |> render_click()
    assert Monitoring.list_endpoints() == []
    assert has_element?(view, "#empty-endpoints")
  end

  test "invalid input stays in the form and is not persisted", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin")

    html =
      view
      |> form("#endpoint-form", endpoint: %{name: "Invalid", url: "ftp://example.com"})
      |> render_submit()

    assert html =~ "must be an HTTP or HTTPS URL"
    assert Monitoring.list_endpoints() == []
    assert has_element?(view, "#endpoint_name[value=Invalid]")
  end

  test "stale edits are rejected while configuration updates reach connected views", %{conn: conn} do
    endpoint = endpoint_fixture()
    {:ok, editor, _} = live(conn, ~p"/admin")
    {:ok, observer, _} = live(conn, ~p"/admin")
    editor |> element("#edit-endpoint-#{endpoint.id}") |> render_click()

    {:ok, _} = Monitoring.update_endpoint(endpoint, %{name: "Changed elsewhere"})
    assert render(observer) =~ "Changed elsewhere"

    html =
      editor |> form("#endpoint-form", endpoint: %{name: "Stale overwrite"}) |> render_submit()

    assert html =~ "Endpoint changed in another session"
    assert Monitoring.get_endpoint(endpoint.id).name == "Changed elsewhere"
  end

  test "editing an endpoint deleted elsewhere gives a recoverable message", %{conn: conn} do
    endpoint = endpoint_fixture()
    {:ok, view, _} = live(conn, ~p"/admin")
    view |> element("#edit-endpoint-#{endpoint.id}") |> render_click()
    {:ok, _} = Monitoring.delete_endpoint(endpoint)
    html = view |> form("#endpoint-form", endpoint: %{name: "Deleted"}) |> render_submit()
    assert html =~ "Endpoint changed in another session"
    assert Monitoring.list_endpoints() == []
  end
end
