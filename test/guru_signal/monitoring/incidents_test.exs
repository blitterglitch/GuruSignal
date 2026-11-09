defmodule GuruSignal.Monitoring.IncidentsTest do
  use GuruSignal.DataCase, async: true
  @moduletag capture_log: true
  import GuruSignal.MonitoringFixtures
  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.{CheckRun, Checks, Endpoint, Incident, Incidents}

  defp time(step), do: DateTime.add(~U[2026-11-09 12:00:00.000000Z], step, :second)

  defp check(endpoint, success, step),
    do: completed_check_fixture(endpoint, success, at: time(step))

  test "third failure opens, second recovery resolves, and a new failure period gets a new incident" do
    endpoint = endpoint_fixture()
    check(endpoint, false, 1)
    check(endpoint, false, 2)
    assert Incidents.active() == []
    third = check(endpoint, false, 3)
    [incident] = Incidents.active()
    assert incident.opened_check_id == third.id
    assert incident.opened_at == third.completed_at
    assert incident.error_category == :unexpected_status
    check(endpoint, false, 4)
    assert length(Incidents.recent()) == 1
    check(endpoint, true, 5)
    assert length(Incidents.active()) == 1
    recovery = check(endpoint, true, 6)
    assert Incidents.active() == []
    resolved = Repo.get!(Incident, incident.id)
    assert resolved.resolved_check_id == recovery.id
    assert resolved.resolved_at == recovery.completed_at
    assert Monitoring.get_endpoint(endpoint.id).consecutive_successes == 2

    for step <- 7..9, do: check(endpoint, false, step)
    [another] = Incidents.active()
    refute another.id == incident.id
    assert length(Incidents.recent()) == 2
  end

  test "alternating outcomes reset both opening and recovery streaks" do
    endpoint = endpoint_fixture()

    for {success, step} <- Enum.with_index([false, false, true, false, false], 1),
        do: check(endpoint, success, step)

    assert Incidents.active() == []
    check(endpoint, false, 6)
    check(endpoint, true, 7)
    check(endpoint, false, 8)
    check(endpoint, true, 9)
    assert length(Incidents.active()) == 1
    check(endpoint, true, 10)
    assert Incidents.active() == []
  end

  test "repeated results cannot advance streaks or repeat transition events" do
    endpoint = endpoint_fixture()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:guru_signal, :incident, :transition],
      &__MODULE__.observe/4,
      {self(), endpoint.id}
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    first = check(endpoint, false, 1)
    assert {:ok, :ignored} = Checks.complete(first.id, %{}, now: time(1))
    assert Monitoring.get_endpoint(endpoint.id).consecutive_failures == 1
    check(endpoint, false, 2)
    refute_received {:incident_transition, _, _}
    third = check(endpoint, false, 3)
    assert_received {:incident_transition, :opened, id}
    assert {:ok, :ignored} = Checks.complete(third.id, %{}, now: time(3))
    refute_received {:incident_transition, _, _}
    success = check(endpoint, true, 4)
    assert {:ok, :ignored} = Checks.complete(success.id, %{}, now: time(4))
    assert length(Incidents.active()) == 1
    recovered = check(endpoint, true, 5)
    assert_received {:incident_transition, :resolved, ^id}
    assert {:ok, :ignored} = Checks.complete(recovered.id, %{}, now: time(5))
    refute_received {:incident_transition, _, _}
  end

  test "configuration edits reset streaks and late results cannot open an incident" do
    endpoint = endpoint_fixture()
    check(endpoint, false, 1)
    check(endpoint, false, 2)
    {:ok, {snapshot, pending}} = Checks.claim(endpoint.id, now: time(3))
    {:ok, edited} = Monitoring.update_endpoint(snapshot, %{url: "https://example.com/new"})
    assert edited.consecutive_failures == 0
    assert {:ok, :discarded} = Checks.complete(pending.id, %{success: false}, now: time(3))
    assert Incidents.active() == []
    check(endpoint, false, 4)
    assert Monitoring.get_endpoint(endpoint.id).consecutive_failures == 1
    assert Incidents.active() == []
  end

  test "saving an older configuration snapshot clears streaks advanced by checks" do
    endpoint = endpoint_fixture()
    check(endpoint, false, 1)
    check(endpoint, false, 2)
    assert Monitoring.get_endpoint(endpoint.id).consecutive_failures == 2

    {:ok, updated} = Monitoring.update_endpoint(endpoint, %{name: "Updated name"})
    assert updated.consecutive_failures == 0
    assert Monitoring.get_endpoint(endpoint.id).consecutive_failures == 0
    check(updated, false, 3)
    assert Monitoring.get_endpoint(endpoint.id).consecutive_failures == 1
    assert Incidents.active() == []
  end

  test "pausing preserves an open incident and re-enabling requires fresh recovery checks" do
    endpoint = endpoint_fixture()
    for step <- 1..3, do: check(endpoint, false, step)
    check(endpoint, true, 4)
    {:ok, {snapshot, pending}} = Checks.claim(endpoint.id, now: time(5))
    {:ok, paused} = Monitoring.update_endpoint(snapshot, %{enabled: false})
    assert paused.consecutive_successes == 0

    assert {:ok, :discarded} =
             Checks.complete(
               pending.id,
               %{success: true, http_status: 200, duration_ms: 1, error_category: nil},
               now: time(5)
             )

    [open] = Incidents.active()
    assert open.endpoint.enabled == false
    {:ok, _} = Monitoring.update_endpoint(paused, %{enabled: true})
    check(endpoint, true, 6)
    assert length(Incidents.active()) == 1
    check(endpoint, true, 7)
    assert Incidents.active() == []
  end

  test "an expired third attempt cannot advance the failure streak" do
    endpoint = endpoint_fixture()
    check(endpoint, false, 1)
    check(endpoint, false, 2)
    {:ok, {_snapshot, pending}} = Checks.claim(endpoint.id, now: time(3))

    outcome = %{
      success: false,
      http_status: 503,
      duration_ms: 1,
      error_category: :unexpected_status
    }

    assert {:ok, :discarded} = Checks.complete(pending.id, outcome, now: pending.lease_expires_at)
    assert Monitoring.get_endpoint(endpoint.id).consecutive_failures == 2
    assert Incidents.active() == []
    check(endpoint, true, 12)
    assert Monitoring.get_endpoint(endpoint.id).consecutive_failures == 0
    assert Incidents.active() == []
  end

  test "invalid result persistence cannot advance counters or create an incident" do
    endpoint = endpoint_fixture()
    check(endpoint, false, 1)
    check(endpoint, false, 2)
    {:ok, {_snapshot, pending}} = Checks.claim(endpoint.id, now: time(3))
    invalid = %{success: true, http_status: 503, duration_ms: 1, error_category: nil}
    assert {:error, %Ecto.Changeset{}} = Checks.complete(pending.id, invalid, now: time(3))
    assert Monitoring.get_endpoint(endpoint.id).consecutive_failures == 2
    assert Repo.get!(CheckRun, pending.id).state == :pending
    assert Incidents.active() == []

    assert {:ok, {:recorded, _}} =
             Checks.complete(
               pending.id,
               %{invalid | success: false, error_category: :unexpected_status},
               now: time(3)
             )

    assert length(Incidents.active()) == 1
  end

  test "the database rejects two open incidents for one endpoint" do
    endpoint = endpoint_fixture()
    for step <- 1..3, do: check(endpoint, false, step)

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.insert_all(Incident, [
          %{endpoint_id: endpoint.id, opened_at: time(4), error_category: :timeout}
        ])
      end

    assert error.postgres.constraint == "incidents_one_open_per_endpoint"
  end

  test "the database rejects impossible streak combinations" do
    endpoint = endpoint_fixture()

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.update_all(from(row in Endpoint, where: row.id == ^endpoint.id),
          set: [consecutive_failures: 1, consecutive_successes: 1]
        )
      end

    assert error.postgres.constraint == "endpoints_valid_streaks"
  end

  test "endpoint deletion removes its incidents and check history" do
    endpoint = endpoint_fixture()
    for step <- 1..3, do: check(endpoint, false, step)
    [incident] = Incidents.active()
    {:ok, _} = Monitoring.delete_endpoint(Monitoring.get_endpoint(endpoint.id))
    assert Repo.get(Incident, incident.id) == nil
    assert Checks.recent() == []
  end

  test "endpoint incident history is scoped, newest first, and bounded" do
    endpoint = endpoint_fixture()
    other = endpoint_fixture()
    for step <- 1..3, do: check(endpoint, false, step)
    [first] = Incidents.recent_for(endpoint.id)
    check(endpoint, true, 4)
    check(endpoint, true, 5)
    for step <- 6..8, do: check(endpoint, false, step)
    for step <- 1..3, do: check(other, false, step)
    [second, resolved] = Incidents.recent_for(endpoint.id)
    assert resolved.id == first.id
    assert resolved.resolved_at
    assert second.resolved_at == nil
    assert [second] == Incidents.recent_for(endpoint.id, 1)
  end

  def observe(_event, _measurements, metadata, {pid, endpoint_id}) do
    if metadata.endpoint_id == endpoint_id do
      send(pid, {:incident_transition, metadata.transition, metadata.incident_id})
    end
  end
end
