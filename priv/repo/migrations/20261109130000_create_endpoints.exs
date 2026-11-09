defmodule GuruSignal.Repo.Migrations.CreateEndpoints do
  use Ecto.Migration

  def change do
    create table(:endpoints) do
      add :name, :string, size: 100, null: false
      add :url, :text, null: false
      add :expected_status, :integer, null: false, default: 200
      add :interval_seconds, :integer, null: false, default: 60
      add :timeout_ms, :integer, null: false, default: 5_000
      add :enabled, :boolean, null: false, default: true
      add :lock_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create constraint(:endpoints, :endpoints_name_length,
             check: "char_length(name) BETWEEN 1 AND 100 AND name ~ '[^[:space:]]'"
           )

    create constraint(:endpoints, :endpoints_url_shape,
             check: "char_length(url) BETWEEN 1 AND 2048 AND url ~ '^https?://'"
           )

    create constraint(:endpoints, :endpoints_expected_status_range,
             check: "expected_status BETWEEN 200 AND 599"
           )

    create constraint(:endpoints, :endpoints_supported_interval,
             check: "interval_seconds IN (60, 300, 900)"
           )

    create constraint(:endpoints, :endpoints_timeout_range,
             check: "timeout_ms BETWEEN 1000 AND 10000"
           )

    create constraint(:endpoints, :endpoints_positive_version, check: "lock_version > 0")
  end
end
