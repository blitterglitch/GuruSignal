defmodule GuruSignal.Monitoring.PublicStatusTest do
  use GuruSignal.DataCase, async: true
  @moduletag capture_log: true
  import GuruSignal.MonitoringFixtures
  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.{Checks, PublicStatus}

  test "projection returns only the explicitly public fields" do
    endpoint =
      endpoint_fixture(%{name: "Public label", url: "https://example.com/private?secret=value"})

    base = DateTime.add(DateTime.utc_now(), -10, :second)

    for step <- 0..2,
        do: completed_check_fixture(endpoint, false, at: DateTime.add(base, step, :second))

    snapshot = PublicStatus.snapshot()
    [service] = snapshot.services
    assert MapSet.new(Map.keys(service)) == MapSet.new([:id, :name, :state, :checked_at])
    assert service.name == "Public label"
    assert service.state == :incident
    [incident] = snapshot.active_incidents
    assert MapSet.new(Map.keys(incident)) == MapSet.new([:id, :name, :opened_at, :resolved_at])
    assert snapshot.recent_incidents == [incident]
    refute inspect(snapshot) =~ "secret=value"
    refute inspect(snapshot) =~ "unexpected_status"
  end

  test "configuration changes hide the previous check from public current state" do
    endpoint = endpoint_fixture()
    completed_check_fixture(endpoint, true)
    assert [%{state: :operational}] = PublicStatus.snapshot().services
    {:ok, updated} = Monitoring.update_endpoint(endpoint, %{url: "https://example.com/new"})
    assert [%{state: :unknown, checked_at: nil}] = PublicStatus.snapshot().services
    {:ok, _} = Monitoring.update_endpoint(updated, %{enabled: false})
    assert [%{state: :paused}] = PublicStatus.snapshot().services
  end

  test "stale successful checks and pending attempts do not establish current health" do
    endpoint = endpoint_fixture()
    now = DateTime.utc_now()
    completed_check_fixture(endpoint, true, at: DateTime.add(now, -80, :second))
    assert [%{state: :unknown}] = PublicStatus.snapshot().services
    {:ok, {_snapshot, _pending}} = Checks.claim(endpoint.id)
    assert [%{state: :unknown}] = PublicStatus.snapshot().services
  end

  test "active incidents are not truncated by the twenty-entry recent history limit" do
    base = DateTime.add(DateTime.utc_now(), -120, :second)
    endpoint = endpoint_fixture(%{name: "Long-running incident"})

    for step <- 0..2,
        do: completed_check_fixture(endpoint, false, at: DateTime.add(base, step, :second))

    for index <- 1..20 do
      other = endpoint_fixture(%{name: "Other service #{index}"})

      for step <- 0..4,
          do:
            completed_check_fixture(other, step >= 3,
              at: DateTime.add(base, 10 + index * 5 + step, :second)
            )
    end

    snapshot = PublicStatus.snapshot()
    assert length(snapshot.recent_incidents) == 20
    assert [%{name: "Long-running incident"}] = snapshot.active_incidents
    refute Enum.any?(snapshot.recent_incidents, &(&1.name == endpoint.name))
  end
end
