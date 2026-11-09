defmodule GuruSignal.Monitoring.CheckRunner do
  @moduledoc "Runs network work outside database transactions and web processes."
  alias GuruSignal.Monitoring.{Checker, Checks}

  def enqueue(id, opts \\ []) do
    Task.Supervisor.start_child(GuruSignal.CheckWorkers, fn -> run(id, opts) end)
  end

  def run(id, opts \\ []) do
    with {:ok, {endpoint, run}} <- Checks.claim(id, opts) do
      outcome = Checker.check(endpoint, opts)
      Checks.complete(run.id, outcome)
    end
  end
end
