defmodule GuruSignal.Monitoring.Scheduler do
  @moduledoc "Single-node, bounded scheduler. Missed intervals are not replayed."
  use GenServer
  require Logger
  alias GuruSignal.Monitoring.{CheckRunner, Checks}

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    enabled =
      Keyword.get(opts, :enabled, Application.get_env(:guru_signal, :monitoring_enabled, false))

    if enabled, do: send(self(), :tick)
    {:ok, %{enabled: enabled}}
  end

  @impl true
  def handle_info(:tick, %{enabled: false} = state), do: {:noreply, state}

  def handle_info(:tick, state) do
    try do
      free = max(4 - length(Task.Supervisor.children(GuruSignal.CheckWorkers)), 0)
      if free > 0, do: Enum.each(Checks.due_ids(free), &CheckRunner.enqueue(&1, scheduled: true))
    rescue
      _error -> Logger.error("Monitoring scheduler could not dispatch checks")
    end

    Process.send_after(self(), :tick, 1_000)
    {:noreply, state}
  end
end
