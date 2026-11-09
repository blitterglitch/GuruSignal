defmodule GuruSignal.Monitoring.HTTPResponseTest do
  use ExUnit.Case, async: true
  alias GuruSignal.Monitoring.HTTPResponse

  test "waits through informational responses and discards bodies" do
    ref = make_ref()

    events = [
      {:status, ref, 100},
      {:headers, ref, []},
      {:status, ref, 200},
      {:headers, ref, []},
      {:data, ref, "discard me"}
    ]

    assert {:ok, result} = HTTPResponse.consume(%HTTPResponse{}, events, ref)
    assert result.status == 200 and result.complete?
    assert result.body_bytes == 10
    refute inspect(result) =~ "discard me"
  end

  test "rejects oversized headers and bodies even when final headers are present" do
    ref = make_ref()

    for events <- [
          [{:headers, ref, [{"large", String.duplicate("x", 16_384)}]}],
          [{:status, ref, 200}, {:headers, ref, []}, {:data, ref, String.duplicate("x", 65_537)}]
        ] do
      assert {:error, :response_limit} = HTTPResponse.consume(%HTTPResponse{}, events, ref)
    end
  end
end
