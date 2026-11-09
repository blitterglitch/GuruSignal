defmodule GuruSignal.Monitoring.Endpoint do
  use Ecto.Schema
  import Ecto.Changeset

  alias GuruSignal.Monitoring.EndpointURL

  @intervals [60, 300, 900]

  schema "endpoints" do
    field :name, :string
    field :url, :string, redact: true
    field :expected_status, :integer, default: 200
    field :interval_seconds, :integer, default: 60
    field :timeout_ms, :integer, default: 5_000
    field :enabled, :boolean, default: true
    field :lock_version, :integer, default: 1
    field :check_sequence, :integer, default: 0
    field :last_check_sequence, :integer, default: 0
    field :next_check_at, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end

  def intervals, do: @intervals

  def changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:name, :url, :expected_status, :interval_seconds, :timeout_ms, :enabled])
    |> update_change(:name, &String.trim/1)
    |> update_change(:url, &String.trim/1)
    |> validate_required([
      :name,
      :url,
      :expected_status,
      :interval_seconds,
      :timeout_ms,
      :enabled
    ])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:url, max: 2_048)
    |> validate_number(:expected_status,
      greater_than_or_equal_to: 200,
      less_than_or_equal_to: 599
    )
    |> validate_inclusion(:interval_seconds, @intervals)
    |> validate_number(:timeout_ms,
      greater_than_or_equal_to: 1_000,
      less_than_or_equal_to: 10_000
    )
    |> validate_change(:url, fn :url, value ->
      case EndpointURL.validate(value) do
        :ok -> []
        {:error, message} -> [url: message]
      end
    end)
    |> check_constraint(:name, name: :endpoints_name_length)
    |> check_constraint(:url, name: :endpoints_url_shape)
    |> check_constraint(:expected_status, name: :endpoints_expected_status_range)
    |> check_constraint(:interval_seconds, name: :endpoints_supported_interval)
    |> check_constraint(:timeout_ms, name: :endpoints_timeout_range)
  end
end
