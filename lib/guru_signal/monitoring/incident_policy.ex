defmodule GuruSignal.Monitoring.IncidentPolicy do
  @moduledoc "Pure three-failure/two-success incident rules for accepted check results."

  def advance(endpoint, true, open?) do
    successes = min(endpoint.consecutive_successes + 1, 2)
    changes = [consecutive_failures: 0, consecutive_successes: successes]
    {changes, if(open? and successes == 2, do: :resolve, else: :none)}
  end

  def advance(endpoint, false, open?) do
    failures = min(endpoint.consecutive_failures + 1, 3)
    changes = [consecutive_failures: failures, consecutive_successes: 0]
    {changes, if(not open? and failures == 3, do: :open, else: :none)}
  end
end
