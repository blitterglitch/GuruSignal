defmodule GuruSignalWeb.AdminLiveTest do
  use GuruSignalWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  import GuruSignal.MonitoringFixtures
  alias GuruSignal.Monitoring
  alias GuruSignal.OwnerAccess
  alias GuruSignal.Monitoring.{Checks, Incidents}

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

  test "completed checks update the endpoint and history without a refresh", %{conn: conn} do
    endpoint = endpoint_fixture()
    {:ok, view, _} = live(conn, ~p"/admin")
    assert has_element?(view, "#endpoint-#{endpoint.id}", "Awaiting check")
    {:ok, {_snapshot, run}} = Checks.claim(endpoint.id)

    outcome = %{
      success: false,
      http_status: 503,
      duration_ms: 123,
      error_category: :unexpected_status
    }

    assert {:ok, {:recorded, _}} = Checks.complete(run.id, outcome)
    assert render(view) =~ "Failing"
    assert has_element?(view, "#check-#{run.id}", "503")
    assert has_element?(view, "#check-#{run.id}", "Unexpected HTTP status")
  end

  test "LiveView mount logs cannot expose the owner session token", %{
    conn: conn,
    owner_token: token
  } do
    previous = Logger.level()
    Logger.configure(level: :debug)

    try do
      logs =
        capture_log([level: :debug], fn ->
          assert {:ok, _view, _html} = live(conn, ~p"/admin")
        end)

      refute logs =~ token
      refute logs =~ "Session:"
    after
      Logger.configure(level: previous)
    end
  end

  test "incident opens after three failures and stays visible until the second recovery success",
       %{conn: conn} do
    endpoint = endpoint_fixture()
    {:ok, view, _} = live(conn, ~p"/admin")
    base = ~U[2026-11-09 12:00:00.000000Z]
    completed_check_fixture(endpoint, false, at: base)
    assert render(view) =~ "Failing (1/3 failures)"
    assert has_element?(view, "#active-incidents", "No active incidents")
    completed_check_fixture(endpoint, false, at: DateTime.add(base, 1, :second))
    completed_check_fixture(endpoint, false, at: DateTime.add(base, 2, :second))
    assert render(view) =~ "Incident open"
    [incident] = Incidents.active()
    assert has_element?(view, "#active-incident-#{incident.id}", "Homepage")

    completed_check_fixture(endpoint, true, at: DateTime.add(base, 3, :second))
    assert render(view) =~ "Recovering (1/2 successes)"
    assert has_element?(view, "#active-incident-#{incident.id}")
    completed_check_fixture(endpoint, true, at: DateTime.add(base, 4, :second))
    assert has_element?(view, "#endpoint-#{endpoint.id}", "Healthy")
    refute has_element?(view, "#active-incident-#{incident.id}")
    assert has_element?(view, "#incident-history-#{incident.id}", "2026-11-09T12:00:04.001000Z")
  end
end
