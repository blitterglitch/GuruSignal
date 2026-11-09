defmodule GuruSignal.Monitoring.PublicStatus do
  @moduledoc "Restricted public projection. Endpoint names are intentionally public labels."
  import Ecto.Query
  alias GuruSignal.Monitoring.{CheckRun, Endpoint, Incident}
  alias GuruSignal.Repo

  def snapshot do
    now = DateTime.utc_now()

    services =
      Repo.all(
        from endpoint in Endpoint,
          left_join: run in CheckRun,
          on:
            run.endpoint_id == endpoint.id and run.sequence == endpoint.last_check_sequence and
              run.endpoint_version == endpoint.lock_version and run.state == :completed,
          left_join: incident in Incident,
          on: incident.endpoint_id == endpoint.id and is_nil(incident.resolved_at),
          order_by: [asc: endpoint.name, asc: endpoint.id],
          select: %{
            id: endpoint.id,
            name: endpoint.name,
            enabled: endpoint.enabled,
            interval_seconds: endpoint.interval_seconds,
            timeout_ms: endpoint.timeout_ms,
            consecutive_successes: endpoint.consecutive_successes,
            incident_open: not is_nil(incident.id),
            success: run.success,
            checked_at: run.checked_at
          }
      )
      |> Enum.map(fn service ->
        %{
          id: service.id,
          name: service.name,
          state: state(service, now),
          checked_at: service.checked_at
        }
      end)

    incidents =
      from incident in Incident,
        join: endpoint in Endpoint,
        on: endpoint.id == incident.endpoint_id,
        order_by: [desc: incident.opened_at, desc: incident.id],
        select: %{
          id: incident.id,
          name: endpoint.name,
          opened_at: incident.opened_at,
          resolved_at: incident.resolved_at
        }

    %{
      services: services,
      active_incidents: Repo.all(from incident in incidents, where: is_nil(incident.resolved_at)),
      recent_incidents: Repo.all(from incident in incidents, limit: 20)
    }
  end

  def state(service, now) do
    fresh = fresh?(service, now)

    cond do
      not service.enabled -> :paused
      service.incident_open and fresh and service.consecutive_successes == 1 -> :recovering
      service.incident_open -> :incident
      not fresh -> :unknown
      service.success -> :operational
      true -> :degraded
    end
  end

  defp fresh?(%{checked_at: nil}, _now), do: false

  defp fresh?(service, now) do
    # One interval, the request budget, and a small dispatch allowance.
    budget_ms = service.interval_seconds * 1_000 + service.timeout_ms + 10_000
    age_ms = DateTime.diff(now, service.checked_at, :millisecond)
    age_ms >= 0 and age_ms <= budget_ms
  end
end
