defmodule GuruSignal.HealthTest do
  use ExUnit.Case, async: true
  alias GuruSignal.Health

  test "requires a successful database probe with the expected result" do
    assert Health.ready?(fn -> {:ok, %{rows: [[1]]}} end)
    refute Health.ready?(fn -> {:ok, %{rows: []}} end)
    refute Health.ready?(fn -> {:error, :unavailable} end)
  end

  test "probe errors, throws, and exits fail closed without logging details" do
    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        refute Health.ready?(fn -> raise "sensitive database failure" end)
        refute Health.ready?(fn -> throw("sensitive database failure") end)
        refute Health.ready?(fn -> exit("sensitive database failure") end)
      end)

    refute logs =~ "sensitive"
  end
end
