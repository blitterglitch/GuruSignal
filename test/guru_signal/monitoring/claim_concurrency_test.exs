defmodule GuruSignal.Monitoring.ClaimConcurrencyTest do
  use ExUnit.Case, async: false
  alias Ecto.Adapters.SQL.Sandbox
  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.Checks
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
        parent = self()

        tasks =
          for _ <- 1..2 do
            Task.async(fn ->
              Sandbox.unboxed_run(Repo, fn ->
                send(parent, {:ready, self()})

                receive do
                  :claim -> Checks.claim(endpoint.id)
                end
              end)
            end)
          end

        for _ <- 1..2, do: assert_receive({:ready, _pid}, 1000)
        Enum.each(tasks, &send(&1.pid, :claim))
        outcomes = Enum.map(tasks, &Task.await(&1, 5000))
        assert Enum.count(outcomes, &match?({:ok, {_endpoint, _run}}, &1)) == 1
        assert Enum.count(outcomes, &(&1 == {:error, :busy})) == 1
        assert Monitoring.get_endpoint(endpoint.id).check_sequence == 1
      after
        Repo.delete_all(from_endpoint(endpoint.id))
      end
    end)
  end

  defp from_endpoint(id) do
    import Ecto.Query
    from endpoint in GuruSignal.Monitoring.Endpoint, where: endpoint.id == ^id
  end
end
