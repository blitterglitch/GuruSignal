defmodule GuruSignalWeb.TelemetryTest do
  use ExUnit.Case, async: true

  test "monitoring metrics use bounded outcome tags and millisecond durations" do
    metrics =
      GuruSignalWeb.Telemetry.metrics()
      |> Enum.filter(
        &(Enum.take(&1.event_name, 2) in [[:guru_signal, :check], [:guru_signal, :incident]])
      )

    assert length(metrics) == 3

    for metric <- metrics do
      assert Enum.all?(metric.tags, &(&1 in [:success, :error_category, :transition]))
    end

    duration = Enum.find(metrics, &(&1.measurement == :duration_ms))
    assert duration.unit == :millisecond
    assert duration.event_name == [:guru_signal, :check, :stop]
    assert Enum.any?(metrics, &(&1.event_name == [:guru_signal, :incident, :transition]))
  end
end
