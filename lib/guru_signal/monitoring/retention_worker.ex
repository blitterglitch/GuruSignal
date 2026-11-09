defmodule GuruSignal.Monitoring.RetentionWorker do
  @moduledoc "Opt-in cleanup of one bounded batch per minute; no startup purge."
  use GenServer
  require Logger
  alias GuruSignal.Monitoring.Retention

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    enabled =
      Keyword.get(opts, :enabled, Application.get_env(:guru_signal, :retention_enabled, false))

    if enabled, do: schedule()
    {:ok, %{enabled: enabled, after_id: 0}}
  end

  @impl true
  def handle_info(:prune, %{enabled: false} = state), do: {:noreply, state}

  def handle_info(:prune, state) do
    after_id =
      try do
        case Retention.prune(after_id: state.after_id) do
          {:ok, result} ->
            result.next_endpoint_id

          {:error, _} ->
            Logger.error("Check history cleanup failed")
            state.after_id
        end
      rescue
        _ ->
          Logger.error("Check history cleanup failed")
          state.after_id
      catch
        kind, _ when kind in [:throw, :exit] ->
          Logger.error("Check history cleanup failed")
          state.after_id
      end

    schedule()
    {:noreply, %{state | after_id: after_id}}
  end

  defp schedule, do: Process.send_after(self(), :prune, 60_000)
end
