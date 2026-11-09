defmodule GuruSignal.Monitoring.Retention do
  @moduledoc "Batched removal of old terminal results, serialized with endpoint writes."
  import Ecto.Query
  require Logger
  alias GuruSignal.Monitoring.{CheckRun, Endpoint}
  alias GuruSignal.Repo

  def prune(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    days = Keyword.get(opts, :days, Application.get_env(:guru_signal, :check_retention_days, 30))
    batch_size = Keyword.get(opts, :batch_size, 1_000)
    after_id = Keyword.get(opts, :after_id, 0)
    validate_options!(days, batch_size, after_id)
    cutoff = DateTime.add(now, -days * 86_400, :second)
    started = System.monotonic_time(:millisecond)

    result = Repo.transaction(fn -> prune_batch(cutoff, batch_size, after_id) end)

    case result do
      {:ok, %{deleted_count: count, endpoint_ids: ids}} ->
        for id <- ids do
          Phoenix.PubSub.broadcast(GuruSignal.PubSub, "monitoring:checks", {:history_pruned, id})
        end

        duration = max(System.monotonic_time(:millisecond) - started, 0)

        :telemetry.execute(
          [:guru_signal, :retention, :stop],
          %{deleted_count: count, duration_ms: duration},
          %{}
        )

        if count > 0,
          do: Logger.info("Old check history pruned", deleted_count: count, duration_ms: duration)

        result

      other ->
        other
    end
  end

  defp prune_batch(cutoff, batch_size, after_id) do
    candidates =
      from run in CheckRun,
        where: run.endpoint_id == parent_as(:endpoint).id,
        where: run.state in [:completed, :discarded] and run.completed_at < ^cutoff,
        where:
          run.sequence != parent_as(:endpoint).check_sequence and
            run.sequence != parent_as(:endpoint).last_check_sequence,
        select: 1

    # Lock endpoints before check/incident rows, as claims and completion do.
    endpoints =
      Repo.all(
        from endpoint in Endpoint,
          as: :endpoint,
          where: endpoint.id > ^after_id and exists(subquery(candidates)),
          order_by: [asc: endpoint.id],
          limit: 50,
          lock: "FOR UPDATE SKIP LOCKED",
          select: %{
            id: endpoint.id,
            check_sequence: endpoint.check_sequence,
            last_check_sequence: endpoint.last_check_sequence
          }
      )

    {count, ids, cursor} =
      Enum.reduce_while(endpoints, {0, [], 0}, fn endpoint, {count, ids, cursor} ->
        if count == batch_size do
          {:halt, {count, ids, cursor}}
        else
          # Re-read eligibility after acquiring the endpoint lock.
          expired_ids =
            Repo.all(
              from run in CheckRun,
                where: run.endpoint_id == ^endpoint.id,
                where: run.state in [:completed, :discarded] and run.completed_at < ^cutoff,
                where:
                  run.sequence != ^endpoint.check_sequence and
                    run.sequence != ^endpoint.last_check_sequence,
                order_by: [asc: run.completed_at, asc: run.id],
                limit: ^(batch_size - count),
                select: run.id
            )

          {deleted, _} = Repo.delete_all(from run in CheckRun, where: run.id in ^expired_ids)
          ids = if deleted > 0, do: [endpoint.id | ids], else: ids
          {:cont, {count + deleted, ids, endpoint.id}}
        end
      end)

    %{deleted_count: count, endpoint_ids: Enum.reverse(ids), next_endpoint_id: cursor}
  end

  defp validate_options!(days, batch_size, after_id) do
    unless is_integer(days) and days in 1..3_650 and is_integer(batch_size) and
             batch_size in 1..1_000 and is_integer(after_id) and after_id >= 0 and
             after_id <= 9_223_372_036_854_775_807 do
      raise ArgumentError,
            "retention days must be 1..3650 and batch size must be 1..1000, and after_id must be a nonnegative database ID"
    end
  end
end
