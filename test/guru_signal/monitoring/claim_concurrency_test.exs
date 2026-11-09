defmodule GuruSignal.Monitoring.ClaimConcurrencyTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true
  import GuruSignal.MonitoringFixtures
  alias Ecto.Adapters.SQL.Sandbox
  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.{Checks, Incident}
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

  defp concurrently(function) do
    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})

            receive do
              :run -> function.()
            end
          end)
        end)
      end

    for _ <- 1..2, do: assert_receive({:ready, _pid}, 1000)
    Enum.each(tasks, &send(&1.pid, :run))
    Enum.map(tasks, &Task.await(&1, 5000))
  end

  defp from_endpoint(id) do
    import Ecto.Query
    from endpoint in GuruSignal.Monitoring.Endpoint, where: endpoint.id == ^id
  end
end
