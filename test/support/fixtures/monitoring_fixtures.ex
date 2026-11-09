defmodule GuruSignal.MonitoringFixtures do
  alias GuruSignal.Monitoring

  def endpoint_fixture(attrs \\ %{}) do
    attrs = Map.merge(%{name: "Homepage", url: "https://example.com/health"}, attrs)
    {:ok, endpoint} = Monitoring.create_endpoint(attrs)
    endpoint
  end
end
