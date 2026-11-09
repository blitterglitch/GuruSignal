defmodule GuruSignal.Monitoring.Incident do
  use Ecto.Schema

  schema "incidents" do
    belongs_to :endpoint, GuruSignal.Monitoring.Endpoint
    belongs_to :opened_check, GuruSignal.Monitoring.CheckRun, type: :binary_id
    belongs_to :resolved_check, GuruSignal.Monitoring.CheckRun, type: :binary_id
    field :opened_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec

    field :error_category, Ecto.Enum,
      values: [
        :connection,
        :tls,
        :timeout,
        :unexpected_status,
        :blocked_destination,
        :response_limit,
        :protocol,
        :internal
      ]
  end
end
