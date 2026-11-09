defmodule GuruSignal.Monitoring.CheckRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @errors [
    :connection,
    :tls,
    :timeout,
    :unexpected_status,
    :blocked_destination,
    :response_limit,
    :protocol,
    :internal
  ]

  schema "check_runs" do
    belongs_to :endpoint, GuruSignal.Monitoring.Endpoint
    field :sequence, :integer
    field :endpoint_version, :integer
    field :expected_status, :integer
    field :state, Ecto.Enum, values: [:pending, :completed, :discarded], default: :pending
    field :checked_at, :utc_datetime_usec
    field :lease_expires_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :success, :boolean
    field :http_status, :integer
    field :duration_ms, :integer
    field :error_category, Ecto.Enum, values: @errors
  end

  def completion_changeset(run, outcome, now) do
    run
    |> cast(outcome, [:success, :http_status, :duration_ms, :error_category])
    |> put_change(:state, :completed)
    |> put_change(:completed_at, now)
    |> validate_required([:success, :duration_ms])
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> validate_number(:http_status, greater_than_or_equal_to: 200, less_than_or_equal_to: 599)
    |> check_constraint(:success, name: :check_runs_result_shape)
  end
end
