defmodule GuruSignal.Monitoring.RetentionTest do
  use GuruSignal.DataCase, async: true
  @moduletag capture_log: true
  import GuruSignal.MonitoringFixtures
  alias GuruSignal.Monitoring.{CheckRun, Checks, Incident, Incidents, PublicStatus, Retention}

  @now ~U[2026-11-09 12:00:00.000000Z]
  @old ~U[2026-09-01 12:00:00.000000Z]

  test "prunes old terminal history in bounded batches and preserves the latest result" do
    endpoint = endpoint_fixture()

    old =
      for step <- 0..3,
          do: completed_check_fixture(endpoint, true, at: DateTime.add(@old, step, :second))

    latest = completed_check_fixture(endpoint, true, at: @now)

    assert {:ok, %{deleted_count: 2, endpoint_ids: [id]}} =
             Retention.prune(now: @now, batch_size: 2)

    assert id == endpoint.id
    assert Repo.get(CheckRun, latest.id)
    assert Enum.count(old, &(Repo.get(CheckRun, &1.id) == nil)) == 2
    assert {:ok, %{deleted_count: 2}} = Retention.prune(now: @now)
    assert {:ok, %{deleted_count: 0, endpoint_ids: []}} = Retention.prune(now: @now)
    assert [latest] == Checks.recent_for(endpoint.id)
  end

  test "preserves pending work, the latest terminal attempt, and the last accepted result" do
    endpoint = endpoint_fixture()
    obsolete = completed_check_fixture(endpoint, true, at: @old)
    latest = completed_check_fixture(endpoint, false, at: DateTime.add(@old, 1, :second))
    {:ok, {_snapshot, expired}} = Checks.claim(endpoint.id, now: DateTime.add(@old, 2, :second))
    assert {:ok, :discarded} = Checks.complete(expired.id, %{}, now: expired.lease_expires_at)
    assert {:ok, %{deleted_count: 1}} = Retention.prune(now: @now)
    assert Repo.get(CheckRun, obsolete.id) == nil
    assert Repo.get(CheckRun, latest.id)
    assert Repo.get(CheckRun, expired.id).state == :discarded
    {:ok, {_snapshot, pending}} = Checks.claim(endpoint.id, now: @now)
    assert {:ok, %{deleted_count: 1}} = Retention.prune(now: @now)
    assert Repo.get(CheckRun, expired.id) == nil
    assert Repo.get(CheckRun, latest.id)
    assert Repo.get(CheckRun, pending.id).state == :pending
  end

  test "incident timestamps and category survive removal of triggering check rows" do
    endpoint = endpoint_fixture()

    for step <- 0..4,
        do: completed_check_fixture(endpoint, step >= 3, at: DateTime.add(@old, step, :second))

    [incident] = Incidents.recent_for(endpoint.id)
    completed_check_fixture(endpoint, true, at: @now)
    before = PublicStatus.snapshot()
    assert {:ok, %{deleted_count: 5}} = Retention.prune(now: @now)
    retained = Repo.get!(Incident, incident.id)
    assert retained.opened_check_id == nil
    assert retained.resolved_check_id == nil
    assert retained.opened_at == incident.opened_at
    assert retained.resolved_at == incident.resolved_at
    assert retained.error_category == incident.error_category
    assert PublicStatus.snapshot() == before
  end

  test "cutoff is strict and uses completion time, and custom day counts are respected" do
    endpoint = endpoint_fixture()
    cutoff = DateTime.add(@now, -30 * 86_400, :second)

    at_cutoff =
      completed_check_fixture(endpoint, true, at: DateTime.add(cutoff, -1, :millisecond))

    recent = completed_check_fixture(endpoint, true, at: DateTime.add(cutoff, 1, :second))
    completed_check_fixture(endpoint, true, at: @now)
    assert {:ok, %{deleted_count: 0}} = Retention.prune(now: @now)
    assert Repo.get(CheckRun, at_cutoff.id)
    assert Repo.get(CheckRun, recent.id)
    assert {:ok, %{deleted_count: 2}} = Retention.prune(now: @now, days: 29)
  end

  test "publishes scoped history changes and safe deletion telemetry after success" do
    endpoint = endpoint_fixture()
    endpoint_id = endpoint.id
    completed_check_fixture(endpoint, true, at: @old)
    completed_check_fixture(endpoint, true, at: @now)
    GuruSignal.Monitoring.subscribe()
    handler = {__MODULE__, make_ref()}
    :telemetry.attach(handler, [:guru_signal, :retention, :stop], &__MODULE__.observe/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
    assert {:ok, %{deleted_count: 1}} = Retention.prune(now: @now)
    assert_received {:history_pruned, ^endpoint_id}
    assert_received {:retention_event, %{deleted_count: 1, duration_ms: duration}, %{}}
    assert duration >= 0
    assert {:ok, %{deleted_count: 0}} = Retention.prune(now: @now)
    refute_received {:history_pruned, ^endpoint_id}
  end

  test "an old open incident still recovers after its opening result is pruned" do
    endpoint = endpoint_fixture()

    for step <- 0..2,
        do: completed_check_fixture(endpoint, false, at: DateTime.add(@old, step, :second))

    [incident] = Incidents.active()
    completed_check_fixture(endpoint, false, at: @now)
    assert {:ok, %{deleted_count: 3}} = Retention.prune(now: @now)
    retained = Repo.get!(Incident, incident.id)
    assert retained.opened_check_id == nil
    assert retained.resolved_at == nil
    completed_check_fixture(endpoint, true, at: DateTime.add(@now, 1, :second))
    completed_check_fixture(endpoint, true, at: DateTime.add(@now, 2, :second))
    assert Incidents.active() == []
    assert Repo.get!(Incident, incident.id).resolved_at
  end

  test "a batch cursor visits later endpoints before returning to an earlier backlog" do
    first = endpoint_fixture()
    second = endpoint_fixture()

    for step <- 0..2,
        do: completed_check_fixture(first, true, at: DateTime.add(@old, step, :second))

    completed_check_fixture(second, true, at: @old)
    completed_check_fixture(second, true, at: @now)
    first_id = first.id
    second_id = second.id

    assert {:ok, %{deleted_count: 1, next_endpoint_id: ^first_id}} =
             Retention.prune(now: @now, batch_size: 1)

    assert {:ok, %{deleted_count: 1, next_endpoint_id: ^second_id}} =
             Retention.prune(now: @now, after_id: first_id)

    assert {:ok, %{deleted_count: 0, next_endpoint_id: 0}} =
             Retention.prune(now: @now, after_id: second_id)

    assert {:ok, %{deleted_count: 1}} = Retention.prune(now: @now)
  end

  def observe(_event, measurements, metadata, pid) do
    if self() == pid, do: send(pid, {:retention_event, measurements, metadata})
  end
end
