defmodule GuruSignal.Monitoring.ClaimConcurrencyTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true
  import GuruSignal.MonitoringFixtures
  alias Ecto.Adapters.SQL.Sandbox
  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.{Checks, Incident, Retention}
  alias GuruSignal.Repo

  test "separate database connections cannot claim the same endpoint concurrently" do
    # Deliberately unboxed: both transactions need independent connections and
    # committed visibility. The only committed fixture is removed in an after block.
    Sandbox.unboxed_run(Repo, fn ->
      {:ok, endpoint} =
        Monitoring.create_endpoint(%{
          name: "Concurrent claim fixture",
          url: "https://example.com"
        })

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn -> Repo.delete_all(from_endpoint(endpoint.id)) end)
      end)

      try do
        outcomes = concurrently(fn -> Checks.claim(endpoint.id) end)
        assert Enum.count(outcomes, &match?({:ok, {_endpoint, _run}}, &1)) == 1
        assert Enum.count(outcomes, &(&1 == {:error, :busy})) == 1
        assert Monitoring.get_endpoint(endpoint.id).check_sequence == 1
      after
        Repo.delete_all(from_endpoint(endpoint.id))
      end
    end)
  end

  test "concurrent completion of the third failure opens exactly one incident" do
    Sandbox.unboxed_run(Repo, fn ->
      endpoint = endpoint_fixture(%{name: "Concurrent incident fixture"})

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn -> Repo.delete_all(from_endpoint(endpoint.id)) end)
      end)

      try do
        now = ~U[2026-11-09 12:00:00.000000Z]
        completed_check_fixture(endpoint, false, at: now)
        completed_check_fixture(endpoint, false, at: DateTime.add(now, 1, :second))
        third_time = DateTime.add(now, 2, :second)
        {:ok, {_snapshot, run}} = Checks.claim(endpoint.id, now: third_time)

        outcome = %{
          success: false,
          http_status: 503,
          duration_ms: 10,
          error_category: :unexpected_status
        }

        outcomes = concurrently(fn -> Checks.complete(run.id, outcome, now: third_time) end)
        assert Enum.count(outcomes, &match?({:ok, {:recorded, _run}}, &1)) == 1
        assert Enum.count(outcomes, &(&1 == {:ok, :ignored})) == 1
        import Ecto.Query

        [incident] =
          Repo.all(from incident in Incident, where: incident.endpoint_id == ^endpoint.id)

        assert incident.opened_check_id == run.id
        assert incident.resolved_at == nil
        assert Monitoring.get_endpoint(endpoint.id).consecutive_failures == 3
      after
        Repo.delete_all(from_endpoint(endpoint.id))
      end
    end)
  end

  test "concurrent completion of the second recovery success resolves exactly once" do
    Sandbox.unboxed_run(Repo, fn ->
      endpoint = endpoint_fixture(%{name: "Concurrent recovery fixture"})

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn -> Repo.delete_all(from_endpoint(endpoint.id)) end)
      end)

      try do
        now = ~U[2026-11-09 12:00:00.000000Z]

        for step <- 0..3 do
          completed_check_fixture(endpoint, step == 3, at: DateTime.add(now, step, :second))
        end

        recovery_time = DateTime.add(now, 4, :second)
        {:ok, {_snapshot, run}} = Checks.claim(endpoint.id, now: recovery_time)
        outcome = %{success: true, http_status: 200, duration_ms: 10, error_category: nil}

        outcomes = concurrently(fn -> Checks.complete(run.id, outcome, now: recovery_time) end)
        assert Enum.count(outcomes, &match?({:ok, {:recorded, _}}, &1)) == 1
        assert Enum.count(outcomes, &(&1 == {:ok, :ignored})) == 1
        [incident] = GuruSignal.Monitoring.Incidents.recent_for(endpoint.id)
        assert incident.resolved_check_id == run.id
        assert incident.resolved_at == recovery_time
        assert Monitoring.get_endpoint(endpoint.id).consecutive_successes == 2
      after
        Repo.delete_all(from_endpoint(endpoint.id))
      end
    end)
  end

  test "a configuration save racing the third failure always resets counters" do
    Sandbox.unboxed_run(Repo, fn ->
      endpoint = endpoint_fixture(%{name: "Concurrent configuration fixture"})

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn -> Repo.delete_all(from_endpoint(endpoint.id)) end)
      end)

      try do
        now = ~U[2026-11-09 12:00:00.000000Z]

        for step <- 0..1,
            do: completed_check_fixture(endpoint, false, at: DateTime.add(now, step, :second))

        completion_time = DateTime.add(now, 2, :second)
        {:ok, {_snapshot, run}} = Checks.claim(endpoint.id, now: completion_time)

        outcome = %{
          success: false,
          http_status: 503,
          duration_ms: 10,
          error_category: :unexpected_status
        }

        [completion, edit] =
          concurrently([
            fn -> Checks.complete(run.id, outcome, now: completion_time) end,
            fn -> Monitoring.update_endpoint(endpoint, %{name: "Edited during completion"}) end
          ])

        assert {:ok, _} = edit
        current = Monitoring.get_endpoint(endpoint.id)
        assert current.lock_version == 2
        assert current.name == "Edited during completion"
        assert current.consecutive_failures == 0
        assert current.consecutive_successes == 0

        case completion do
          {:ok, {:recorded, recorded}} ->
            # Completion acquired the lock first; editing preserves its incident.
            [incident] = GuruSignal.Monitoring.Incidents.recent_for(endpoint.id)
            assert incident.opened_check_id == recorded.id

          {:ok, :discarded} ->
            # Editing acquired the lock first; the old configuration cannot open one.
            assert GuruSignal.Monitoring.Incidents.recent_for(endpoint.id) == []
        end
      after
        Repo.delete_all(from_endpoint(endpoint.id))
      end
    end)
  end

  test "cleanup skips an endpoint locked by another connection and retries later" do
    with_retention_fixture(fn endpoint, now ->
      Repo.transaction(fn ->
        import Ecto.Query

        Repo.one!(
          from row in GuruSignal.Monitoring.Endpoint,
            where: row.id == ^endpoint.id,
            lock: "FOR UPDATE"
        )

        task =
          Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> Retention.prune(now: now) end) end)

        assert {:ok, %{deleted_count: 0}} = Task.await(task, 2000)
      end)

      assert {:ok, %{deleted_count: 2}} = Retention.prune(now: now)
    end)
  end

  test "simultaneous cleanup batches cannot delete current state or double-count rows" do
    with_retention_fixture(fn endpoint, now ->
      outcomes = concurrently(fn -> Retention.prune(now: now, batch_size: 1) end)

      deleted =
        Enum.reduce(outcomes, 0, fn {:ok, result}, count -> count + result.deleted_count end)

      assert deleted in 1..2
      assert length(Checks.recent_for(endpoint.id)) == 3 - deleted
      assert {:ok, %{deleted_count: remaining}} = Retention.prune(now: now)
      assert remaining == 2 - deleted
      assert [latest] = Checks.recent_for(endpoint.id)
      assert latest.sequence == 3
    end)
  end

  test "cleanup racing completion preserves the newly accepted result" do
    with_retention_fixture(
      fn endpoint, now ->
        {:ok, {_snapshot, pending}} = Checks.claim(endpoint.id, now: now)
        outcome = %{success: true, http_status: 200, duration_ms: 10, error_category: nil}

        [cleanup, completion] =
          concurrently([
            fn -> Retention.prune(now: now) end,
            fn -> Checks.complete(pending.id, outcome, now: now) end
          ])

        assert {:ok, %{deleted_count: deleted}} = cleanup
        # Zero when completion holds the lock; two when cleanup runs first;
        # three when cleanup runs after completion has advanced current state.
        assert deleted in [0, 2, 3]
        assert {:ok, {:recorded, run}} = completion
        assert run.id == pending.id
        assert Monitoring.get_endpoint(endpoint.id).last_check_sequence == run.sequence
        assert hd(Checks.recent_for(endpoint.id)).id == run.id
        assert length(Checks.recent_for(endpoint.id)) == 4 - deleted
        assert {:ok, %{deleted_count: remaining}} = Retention.prune(now: now)
        assert remaining == 3 - deleted
        assert [run] == Checks.recent_for(endpoint.id)
      end,
      latest_old: true
    )
  end

  defp with_retention_fixture(function, opts \\ []) do
    Sandbox.unboxed_run(Repo, fn ->
      endpoint = endpoint_fixture(%{name: "Retention concurrency fixture"})

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn -> Repo.delete_all(from_endpoint(endpoint.id)) end)
      end)

      try do
        old = ~U[2026-09-01 12:00:00.000000Z]
        now = ~U[2026-11-09 12:00:00.000000Z]
        completed_check_fixture(endpoint, true, at: old)
        completed_check_fixture(endpoint, true, at: DateTime.add(old, 1, :second))

        latest_time =
          if Keyword.get(opts, :latest_old, false), do: DateTime.add(old, 2, :second), else: now

        completed_check_fixture(endpoint, true, at: latest_time)
        function.(endpoint, now)
      after
        Repo.delete_all(from_endpoint(endpoint.id))
      end
    end)
  end

  defp concurrently(function) when is_function(function, 0),
    do: concurrently([function, function])

  defp concurrently(functions) do
    parent = self()

    tasks =
      for function <- functions do
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})

            receive do
              :run -> function.()
            end
          end)
        end)
      end

    for _ <- functions, do: assert_receive({:ready, _pid}, 1000)
    Enum.each(tasks, &send(&1.pid, :run))
    Enum.map(tasks, &Task.await(&1, 5000))
  end

  defp from_endpoint(id) do
    import Ecto.Query
    from endpoint in GuruSignal.Monitoring.Endpoint, where: endpoint.id == ^id
  end
end
