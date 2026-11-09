defmodule GuruSignal.Health do
  @moduledoc "Database readiness without exposing connection failures or monitored-service health."
  alias GuruSignal.Repo

  def ready?(probe \\ &database_probe/0) do
    case probe.() do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  rescue
    _error -> false
  catch
    kind, _reason when kind in [:throw, :exit] -> false
  end

  defp database_probe do
    Repo.query("SELECT 1", [], timeout: 1_000, log: false)
  end
end
