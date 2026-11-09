defmodule GuruSignal.Monitoring.Checks do
  @moduledoc "Transactional claims and idempotent application of endpoint check results."
  import Ecto.Query
  require Logger
  alias GuruSignal.Monitoring.{CheckRun, Endpoint, Incidents}
  alias GuruSignal.Repo
  @topic "monitoring:checks"

  def due_ids(limit) do
    now = DateTime.utc_now()

    query =
      from endpoint in Endpoint,
        where:
          endpoint.enabled and (is_nil(endpoint.next_check_at) or endpoint.next_check_at <= ^now),
        order_by: [asc_nulls_first: endpoint.next_check_at, asc: endpoint.id],
        limit: ^limit,
        select: endpoint.id

    Repo.all(query, log: false)
  end

  def claim(id, opts \\ []) do
    Repo.transaction(fn ->
      endpoint = lock_endpoint(id) || Repo.rollback(:not_found)
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      unless endpoint.enabled, do: Repo.rollback(:disabled)

      if Keyword.get(opts, :scheduled, false) and not is_nil(endpoint.next_check_at) and
           DateTime.compare(endpoint.next_check_at, now) == :gt do
        Repo.rollback(:not_due)
      end

      previous =
        Repo.one(
          from run in CheckRun,
            where: run.endpoint_id == ^endpoint.id and run.sequence == ^endpoint.check_sequence
        )

      if previous && previous.state == :pending do
        if DateTime.compare(previous.lease_expires_at, now) == :gt do
          Repo.rollback(:busy)
        end

        discard(previous, now)
      end

      sequence = endpoint.check_sequence + 1

      run =
        Repo.insert!(%CheckRun{
          endpoint_id: endpoint.id,
          sequence: sequence,
          endpoint_version: endpoint.lock_version,
          expected_status: endpoint.expected_status,
          checked_at: now,
          lease_expires_at: DateTime.add(now, endpoint.timeout_ms + 2_000, :millisecond)
        })

      endpoint =
        endpoint
        |> Ecto.Changeset.change(
          check_sequence: sequence,
          next_check_at: DateTime.add(now, endpoint.interval_seconds, :second)
        )
        |> Repo.update!()

      {endpoint, run}
    end)
  end

  def complete(id, outcome, opts \\ []) do
    result =
      Repo.transaction(fn ->
        initial = Repo.get(CheckRun, id) || Repo.rollback(:not_found)
        endpoint = lock_endpoint(initial.endpoint_id) || Repo.rollback(:not_found)
        run = Repo.get(CheckRun, id) || Repo.rollback(:not_found)
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

        cond do
          run.state != :pending ->
            :ignored

          not endpoint.enabled or endpoint.lock_version != run.endpoint_version or
            endpoint.check_sequence != run.sequence or
              DateTime.compare(run.lease_expires_at, now) != :gt ->
            discard(run, now)
            :discarded

          true ->
            case run |> CheckRun.completion_changeset(outcome, now) |> Repo.update() do
              {:ok, completed} ->
                transition = Incidents.apply_result(endpoint, completed)
                {:recorded, completed, transition}

              {:error, changeset} ->
                Repo.rollback(changeset)
            end
        end
      end)

    case result do
      {:ok, {:recorded, run, transition}} ->
        Phoenix.PubSub.broadcast(GuruSignal.PubSub, @topic, {:check_completed, run.endpoint_id})

        :telemetry.execute([:guru_signal, :check, :stop], %{duration_ms: run.duration_ms}, %{
          endpoint_id: run.endpoint_id,
          success: run.success,
          error_category: run.error_category
        })

        Logger.info("Endpoint check completed",
          endpoint_id: run.endpoint_id,
          check_id: run.id,
          success: run.success,
          duration_ms: run.duration_ms,
          http_status: run.http_status,
          error_category: run.error_category
        )

        Incidents.notify_transition(transition)
        {:ok, {:recorded, run}}

      other ->
        other
    end
  end

  def latest_for(endpoints) do
    ids = Enum.map(endpoints, & &1.id)

    Repo.all(
      from run in CheckRun,
        where: run.endpoint_id in ^ids and run.state == :completed,
        distinct: run.endpoint_id,
        order_by: [asc: run.endpoint_id, desc: run.sequence]
    )
    |> Map.new(&{&1.endpoint_id, &1})
  end

  def recent(limit \\ 20) do
    Repo.all(
      from run in CheckRun,
        where: run.state == :completed,
        order_by: [desc: run.checked_at, desc: run.sequence, desc: run.id],
        limit: ^limit,
        preload: :endpoint
    )
  end

  def recent_for(endpoint_id, limit \\ 50) do
    Repo.all(
      from run in CheckRun,
        where: run.endpoint_id == ^endpoint_id and run.state == :completed,
        order_by: [desc: run.sequence],
        limit: ^limit
    )
  end

  defp discard(run, now) do
    run |> Ecto.Changeset.change(state: :discarded, completed_at: now) |> Repo.update!()
  end

  defp lock_endpoint(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, value} when is_integer(value) and value > 0 and value <= 9_223_372_036_854_775_807 ->
        Repo.one(from endpoint in Endpoint, where: endpoint.id == ^value, lock: "FOR UPDATE")

      _ ->
        nil
    end
  end
end
