defmodule GuruSignal.Monitoring do
  @moduledoc "Endpoint configuration. Web callers must authenticate the owner."
  import Ecto.Query
  import Ecto.Changeset, only: [optimistic_lock: 2]

  alias GuruSignal.Monitoring.Endpoint
  alias GuruSignal.Repo

  @topic "monitoring:endpoints"
  @stale_options [
    stale_error_field: :lock_version,
    stale_error_message: "has changed; reopen the endpoint and try again"
  ]

  def subscribe, do: Phoenix.PubSub.subscribe(GuruSignal.PubSub, @topic)

  def list_endpoints do
    Repo.all(from endpoint in Endpoint, order_by: [asc: endpoint.name, asc: endpoint.id])
  end

  def get_endpoint(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, value} when value > 0 and value <= 9_223_372_036_854_775_807 ->
        Repo.get(Endpoint, value)

      _ ->
        nil
    end
  end

  def change_endpoint(endpoint, attrs \\ %{}), do: Endpoint.changeset(endpoint, attrs)

  def create_endpoint(attrs) do
    %Endpoint{}
    |> Endpoint.changeset(attrs)
    |> Repo.insert()
    |> broadcast_change()
  end

  def update_endpoint(%Endpoint{} = endpoint, attrs) do
    endpoint
    |> Endpoint.changeset(attrs)
    |> optimistic_lock(:lock_version)
    |> Repo.update([force: true] ++ @stale_options)
    |> broadcast_change()
  end

  def delete_endpoint(%Endpoint{} = endpoint) do
    endpoint
    |> Ecto.Changeset.change()
    |> optimistic_lock(:lock_version)
    |> Repo.delete(@stale_options)
    |> broadcast_change()
  end

  defp broadcast_change({:ok, endpoint} = result) do
    Phoenix.PubSub.broadcast(GuruSignal.PubSub, @topic, {:endpoint_changed, endpoint.id})
    result
  end

  defp broadcast_change(error), do: error
end
