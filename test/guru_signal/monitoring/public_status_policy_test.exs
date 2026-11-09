defmodule GuruSignal.Monitoring.PublicStatusPolicyTest do
  use ExUnit.Case, async: true
  alias GuruSignal.Monitoring.PublicStatus

  @now ~U[2026-11-09 12:00:00.000000Z]
  @service %{
    enabled: true,
    interval_seconds: 60,
    timeout_ms: 5_000,
    consecutive_successes: 0,
    incident_open: false,
    success: true,
    checked_at: @now
  }

  test "fresh results distinguish success and a failure before the incident threshold" do
    assert PublicStatus.state(@service, @now) == :operational
    assert PublicStatus.state(%{@service | success: false}, @now) == :degraded
  end

  test "unconfirmed, stale, and future results cannot establish health" do
    assert PublicStatus.state(%{@service | checked_at: nil, success: nil}, @now) == :unknown
    assert PublicStatus.state(@service, DateTime.add(@now, 75_000, :millisecond)) == :operational
    assert PublicStatus.state(@service, DateTime.add(@now, 75_001, :millisecond)) == :unknown
    assert PublicStatus.state(@service, DateTime.add(@now, -1, :millisecond)) == :unknown
  end

  test "open incidents remain open without fresh checks and recovery needs a fresh success" do
    open = %{@service | incident_open: true}
    assert PublicStatus.state(open, @now) == :incident
    recovering = %{open | consecutive_successes: 1}
    assert PublicStatus.state(recovering, @now) == :recovering
    assert PublicStatus.state(recovering, DateTime.add(@now, 76, :second)) == :incident
  end

  test "paused monitoring never implies operational health" do
    assert PublicStatus.state(%{@service | enabled: false}, @now) == :paused
    assert PublicStatus.state(%{@service | enabled: false, incident_open: true}, @now) == :paused
  end
end
