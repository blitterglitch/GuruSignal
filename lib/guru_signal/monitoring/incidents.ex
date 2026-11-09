defmodule GuruSignal.Monitoring.Incidents do
  @moduledoc "Incident persistence; result application requires the endpoint lock held by Checks.complete/3."
  import Ecto.Query
  require Logger
  alias GuruSignal.Monitoring.{Incident, IncidentPolicy}
  alias GuruSignal.Repo

  def active do
    Repo.all(
      from incident in Incident,
        where: is_nil(incident.resolved_at),
        order_by: [desc: incident.opened_at, desc: incident.id],
        preload: :endpoint
    )
  end

  def recent(limit \\ 20) do
    Repo.all(
      from incident in Incident,
        order_by: [desc: incident.opened_at, desc: incident.id],
        limit: ^limit,
        preload: :endpoint
    )
  end

  def apply_result(endpoint, run) do
    open =
      Repo.one(
        from incident in Incident,
          where: incident.endpoint_id == ^endpoint.id and is_nil(incident.resolved_at)
      )

    {streaks, action} = IncidentPolicy.advance(endpoint, run.success, not is_nil(open))

    endpoint
    |> Ecto.Changeset.change([last_check_sequence: run.sequence] ++ streaks)
    |> Repo.update!()

    case action do
      :open ->
        incident =
          Repo.insert!(%Incident{
            endpoint_id: endpoint.id,
            opened_check_id: run.id,
            opened_at: run.completed_at,
            error_category: run.error_category
          })

        {:opened, incident}

      :resolve ->
        incident =
          open
          |> Ecto.Changeset.change(resolved_check_id: run.id, resolved_at: run.completed_at)
          |> Repo.update!()

        {:resolved, incident}

      :none ->
        nil
    end
  end

  # Called only after the transaction containing check, counters, and incident commits.
  def notify_transition(nil), do: :ok

  def notify_transition({action, incident}) do
    check_id =
      if action == :opened, do: incident.opened_check_id, else: incident.resolved_check_id

    metadata = %{
      transition: action,
      endpoint_id: incident.endpoint_id,
      incident_id: incident.id,
      check_id: check_id,
      error_category: incident.error_category
    }

    :telemetry.execute([:guru_signal, :incident, :transition], %{count: 1}, metadata)
    level = if action == :opened, do: :warning, else: :info
    Logger.log(level, "Incident #{action}", Map.to_list(metadata))
  end
end
