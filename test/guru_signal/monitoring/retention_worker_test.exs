defmodule GuruSignal.Monitoring.RetentionWorkerTest do
  use ExUnit.Case, async: true
  alias GuruSignal.Monitoring.{Retention, RetentionWorker}

  test "disabled cleanup schedules no work and ignores prune messages" do
    {:ok, state} = RetentionWorker.init(enabled: false)
    assert state == %{enabled: false, after_id: 0}
    refute_received :prune
    assert {:noreply, ^state} = RetentionWorker.handle_info(:prune, state)
  end

  test "invalid retention bounds are rejected before database access" do
    for options <- [
          [days: 0],
          [days: 3651],
          [days: "30"],
          [batch_size: 0],
          [batch_size: 1001],
          [after_id: -1]
        ] do
      assert_raise ArgumentError, fn -> Retention.prune(options) end
    end
  end
end
