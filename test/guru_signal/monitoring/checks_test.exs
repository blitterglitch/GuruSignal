defmodule GuruSignal.Monitoring.ChecksTest do
  use GuruSignal.DataCase, async: true
  import GuruSignal.MonitoringFixtures
  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.{CheckRun, Checks}

  @success %{success: true, http_status: 200, duration_ms: 42, error_category: nil}

  test "claims enabled endpoints once and applies a completion exactly once" do
    endpoint = endpoint_fixture()
    assert {:ok, {snapshot, run}} = Checks.claim(endpoint.id)
    assert snapshot.lock_version == endpoint.lock_version
    assert snapshot.check_sequence == 1
    assert {:error, :busy} = Checks.claim(endpoint.id)
    Monitoring.subscribe()
    assert {:ok, {:recorded, completed}} = Checks.complete(run.id, @success)
    assert completed.success and completed.duration_ms == 42
    assert_receive {:check_completed, _}

    assert {:ok, :ignored} =
             Checks.complete(run.id, %{
               success: false,
               error_category: :timeout,
               duration_ms: 1000
             })

    refute_received {:check_completed, _}
    assert Repo.get!(CheckRun, run.id).success
    assert Monitoring.get_endpoint(endpoint.id).last_check_sequence == 1
    assert Checks.latest_for([endpoint])[endpoint.id].id == run.id
  end

  test "configuration edits and disabling invalidate in-flight results" do
    for attrs <- [%{url: "https://example.com/new"}, %{enabled: false}] do
      endpoint = endpoint_fixture()
      {:ok, {snapshot, run}} = Checks.claim(endpoint.id)
      {:ok, _} = Monitoring.update_endpoint(snapshot, attrs)
      assert {:ok, :discarded} = Checks.complete(run.id, @success)
      assert Repo.get!(CheckRun, run.id).state == :discarded
      assert Monitoring.get_endpoint(endpoint.id).last_check_sequence == 0
    end
  end

  test "expired claims are superseded and their late results cannot apply" do
    now = DateTime.utc_now()
    endpoint = endpoint_fixture()
    {:ok, {_snapshot, old}} = Checks.claim(endpoint.id, now: now)
    later = DateTime.add(old.lease_expires_at, 1, :second)
    assert {:ok, {_snapshot, current}} = Checks.claim(endpoint.id, now: later)
    assert current.sequence == old.sequence + 1
    assert {:ok, :ignored} = Checks.complete(old.id, @success, now: later)
    assert {:ok, {:recorded, _}} = Checks.complete(current.id, @success, now: later)
    assert Checks.latest_for([endpoint])[endpoint.id].id == current.id
  end

  test "completion after a lease expires is discarded even without a newer claim" do
    endpoint = endpoint_fixture()
    {:ok, {_snapshot, run}} = Checks.claim(endpoint.id)
    assert {:ok, :discarded} = Checks.complete(run.id, @success, now: run.lease_expires_at)
  end

  test "scheduled work skips future due times and disabled endpoints" do
    endpoint = endpoint_fixture()
    assert endpoint.id in Checks.due_ids(10)
    {:ok, {snapshot, run}} = Checks.claim(endpoint.id)
    {:ok, _} = Checks.complete(run.id, @success)
    assert {:error, :not_due} = Checks.claim(endpoint.id, scheduled: true)
    {:ok, _} = Monitoring.update_endpoint(snapshot, %{enabled: false})
    assert {:error, :disabled} = Checks.claim(endpoint.id)
    refute endpoint.id in Checks.due_ids(10)
    assert {:error, :not_found} = Checks.claim("invalid")
  end

  test "deleting an endpoint cascades its claims and history" do
    endpoint = endpoint_fixture()
    {:ok, {snapshot, run}} = Checks.claim(endpoint.id)
    {:ok, _} = Monitoring.delete_endpoint(snapshot)
    assert Repo.get(CheckRun, run.id) == nil
    assert {:error, :not_found} = Checks.complete(run.id, @success)
  end

  test "the database enforces result consistency independently of changesets" do
    endpoint = endpoint_fixture()
    {:ok, {_snapshot, run}} = Checks.claim(endpoint.id)

    assert_raise Postgrex.Error, fn ->
      Repo.update_all(from(check in CheckRun, where: check.id == ^run.id),
        set: [state: :completed, success: true]
      )
    end
  end

  test "endpoint history contains only its completed results in sequence order with a limit" do
    endpoint = endpoint_fixture()
    other = endpoint_fixture()
    base = ~U[2026-11-09 12:00:00.000000Z]
    first = completed_check_fixture(endpoint, true, at: base)
    second = completed_check_fixture(endpoint, false, at: DateTime.add(base, 1, :second))
    third = completed_check_fixture(endpoint, true, at: DateTime.add(base, 2, :second))
    completed_check_fixture(other, false, at: base)
    {:ok, {_snapshot, _pending}} = Checks.claim(endpoint.id, now: DateTime.add(base, 3, :second))
    assert Enum.map(Checks.recent_for(endpoint.id), & &1.id) == [third.id, second.id, first.id]
    assert Enum.map(Checks.recent_for(endpoint.id, 2), & &1.id) == [third.id, second.id]
  end
end
