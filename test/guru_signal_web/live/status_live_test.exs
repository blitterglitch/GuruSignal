defmodule GuruSignalWeb.StatusLiveTest do
  use GuruSignalWeb.ConnCase, async: true
  @moduletag capture_log: true
  import Phoenix.LiveViewTest
  import GuruSignal.MonitoringFixtures
  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.Incidents

  test "home is a read-only status page without authentication", %{conn: conn} do
    response = get(conn, ~p"/")
    assert html_response(response, 200) =~ "Service status"
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#empty-services")
    assert has_element?(view, "#empty-public-history")
    refute has_element?(view, "form")
    refute has_element?(view, "a[href='/admin']")
    assert redirected_to(get(build_conn(), ~p"/admin")) == ~p"/login"
  end

  test "public updates show incident recovery without URLs or diagnostic details", %{conn: conn} do
    endpoint =
      endpoint_fixture(%{
        name: "Public service",
        url: "https://example.com/private?secret=do-not-publish"
      })

    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#service-#{endpoint.id}", "Unknown")
    base = DateTime.add(DateTime.utc_now(), -10, :second)
    completed_check_fixture(endpoint, false, at: base)
    assert has_element?(view, "#service-#{endpoint.id}", "Check failing")

    for step <- 1..2,
        do: completed_check_fixture(endpoint, false, at: DateTime.add(base, step, :second))

    assert has_element?(view, "#service-#{endpoint.id}", "Incident open")
    [incident] = Incidents.active()
    assert has_element?(view, "#public-active-incident-#{incident.id}", "Public service")
    completed_check_fixture(endpoint, true, at: DateTime.add(base, 3, :second))
    assert has_element?(view, "#service-#{endpoint.id}", "Recovering")
    completed_check_fixture(endpoint, true, at: DateTime.add(base, 4, :second))
    assert has_element?(view, "#service-#{endpoint.id}", "Operational")
    refute has_element?(view, "#public-active-incident-#{incident.id}")
    assert has_element?(view, "#public-incident-#{incident.id}", "Resolved")
    html = render(view)

    for secret <- [
          endpoint.url,
          "do-not-publish",
          "unexpected_status",
          "Unexpected HTTP status",
          "Expected HTTP",
          "Request timeout"
        ] do
      refute html =~ secret
    end

    refute has_element?(view, "button[phx-click]")
  end

  test "public view updates for edits, pausing, and deletion", %{conn: conn} do
    endpoint = endpoint_fixture()
    {:ok, view, _} = live(conn, ~p"/")

    {:ok, paused} =
      Monitoring.update_endpoint(endpoint, %{name: "Renamed public label", enabled: false})

    assert has_element?(view, "#service-#{endpoint.id}", "Renamed public label")
    assert has_element?(view, "#service-#{endpoint.id}", "Monitoring paused")
    {:ok, _} = Monitoring.delete_endpoint(paused)
    refute has_element?(view, "#service-#{endpoint.id}")
    assert has_element?(view, "#empty-services")
  end

  test "periodic refresh notices aging checks even without a completion broadcast", %{conn: conn} do
    endpoint = endpoint_fixture()
    run = completed_check_fixture(endpoint, true)
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#service-#{endpoint.id}", "Operational")
    import Ecto.Query

    GuruSignal.Repo.update_all(
      from(check in GuruSignal.Monitoring.CheckRun, where: check.id == ^run.id),
      set: [checked_at: DateTime.add(run.checked_at, -80, :second)]
    )

    send(view.pid, :refresh_status)
    assert has_element?(view, "#service-#{endpoint.id}", "Unknown")
  end
end
