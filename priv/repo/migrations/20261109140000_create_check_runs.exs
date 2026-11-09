defmodule GuruSignal.Repo.Migrations.CreateCheckRuns do
  use Ecto.Migration

  def change do
    alter table(:endpoints) do
      add :check_sequence, :bigint, null: false, default: 0
      add :last_check_sequence, :bigint, null: false, default: 0
      add :next_check_at, :utc_datetime_usec
    end

    create index(:endpoints, [:next_check_at], where: "enabled = true")

    create table(:check_runs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :endpoint_id, references(:endpoints, on_delete: :delete_all), null: false
      add :sequence, :bigint, null: false
      add :endpoint_version, :integer, null: false
      add :expected_status, :integer, null: false
      add :state, :text, null: false, default: "pending"
      add :checked_at, :utc_datetime_usec, null: false
      add :lease_expires_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :success, :boolean
      add :http_status, :integer
      add :duration_ms, :integer
      add :error_category, :text
    end

    create unique_index(:check_runs, [:endpoint_id, :sequence])

    create unique_index(:check_runs, [:endpoint_id],
             where: "state = 'pending'",
             name: :check_runs_one_pending_per_endpoint
           )

    create index(:check_runs, [:checked_at])

    create constraint(:check_runs, :check_runs_positive_sequence,
             check:
               "sequence > 0 AND endpoint_version > 0 AND expected_status BETWEEN 200 AND 599"
           )

    create constraint(:check_runs, :check_runs_valid_lease,
             check: "lease_expires_at > checked_at"
           )

    create constraint(:check_runs, :check_runs_result_shape,
             check: """
               (state = 'pending' AND completed_at IS NULL AND success IS NULL AND http_status IS NULL AND duration_ms IS NULL AND error_category IS NULL)
               OR (state = 'discarded' AND completed_at IS NOT NULL AND success IS NULL AND http_status IS NULL AND duration_ms IS NULL AND error_category IS NULL)
               OR (state = 'completed' AND completed_at IS NOT NULL AND success IS NOT NULL AND duration_ms IS NOT NULL AND duration_ms >= 0
                   AND (http_status IS NULL OR http_status BETWEEN 200 AND 599)
                   AND ((success = true AND http_status IS NOT NULL AND http_status = expected_status AND error_category IS NULL)
                     OR (success = false AND error_category IS NOT NULL AND error_category IN ('connection','tls','timeout','unexpected_status','blocked_destination','response_limit','protocol','internal')
                         AND (error_category <> 'unexpected_status' OR (http_status IS NOT NULL AND http_status <> expected_status)))))
             """
           )

    create constraint(:endpoints, :endpoints_check_sequence_order,
             check:
               "check_sequence >= 0 AND last_check_sequence >= 0 AND last_check_sequence <= check_sequence"
           )
  end
end
