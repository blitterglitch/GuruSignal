defmodule GuruSignal.MonitoringFixtures do
  alias GuruSignal.Monitoring

  def endpoint_fixture(attrs \\ %{}) do
    attrs = Map.merge(%{name: "Homepage", url: "https://example.com/health"}, attrs)
    {:ok, endpoint} = Monitoring.create_endpoint(attrs)
    endpoint
  end

  def completed_check_fixture(endpoint, success, opts \\ []) do
    now = Keyword.get_lazy(opts, :at, &DateTime.utc_now/0)
    {:ok, {snapshot, claim}} = GuruSignal.Monitoring.Checks.claim(endpoint.id, now: now)
    mismatch = if snapshot.expected_status == 503, do: 502, else: 503

    outcome = %{
      success: success,
      http_status: if(success, do: snapshot.expected_status, else: mismatch),
      duration_ms: 10,
      error_category: if(success, do: nil, else: :unexpected_status)
    }

    {:ok, {:recorded, run}} =
      GuruSignal.Monitoring.Checks.complete(claim.id, outcome,
        now: DateTime.add(now, 1, :millisecond)
      )

    run
  end
end
