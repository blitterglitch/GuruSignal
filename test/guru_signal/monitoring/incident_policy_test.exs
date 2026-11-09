defmodule GuruSignal.Monitoring.IncidentPolicyTest do
  use ExUnit.Case, async: true
  alias GuruSignal.Monitoring.{Endpoint, IncidentPolicy}

  test "one or two failures do not open an incident" do
    assert {[consecutive_failures: 1, consecutive_successes: 0], :none} =
             IncidentPolicy.advance(%Endpoint{}, false, false)

    assert {[consecutive_failures: 2, consecutive_successes: 0], :none} =
             IncidentPolicy.advance(%Endpoint{consecutive_failures: 1}, false, false)
  end

  test "the third failure opens once and ongoing failures preserve the incident" do
    endpoint = %Endpoint{consecutive_failures: 2}

    assert {[consecutive_failures: 3, consecutive_successes: 0], :open} =
             IncidentPolicy.advance(endpoint, false, false)

    assert {[consecutive_failures: 3, consecutive_successes: 0], :none} =
             IncidentPolicy.advance(%Endpoint{consecutive_failures: 3}, false, true)
  end

  test "two consecutive successes are required to resolve an open incident" do
    assert {[consecutive_failures: 0, consecutive_successes: 1], :none} =
             IncidentPolicy.advance(%Endpoint{consecutive_failures: 3}, true, true)

    assert {[consecutive_failures: 0, consecutive_successes: 2], :resolve} =
             IncidentPolicy.advance(%Endpoint{consecutive_successes: 1}, true, true)
  end

  test "success resets failures and failure resets recovery progress" do
    assert {[consecutive_failures: 0, consecutive_successes: 1], :none} =
             IncidentPolicy.advance(%Endpoint{consecutive_failures: 2}, true, false)

    assert {[consecutive_failures: 1, consecutive_successes: 0], :none} =
             IncidentPolicy.advance(%Endpoint{consecutive_successes: 1}, false, true)
  end

  test "healthy checks without an incident never cause a resolve transition" do
    assert {[consecutive_failures: 0, consecutive_successes: 2], :none} =
             IncidentPolicy.advance(%Endpoint{consecutive_successes: 2}, true, false)
  end
end
