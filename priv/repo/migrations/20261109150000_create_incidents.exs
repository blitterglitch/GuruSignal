defmodule GuruSignal.Repo.Migrations.CreateIncidents do
  use Ecto.Migration

  def change do
    alter table(:endpoints) do
      add :consecutive_failures, :integer, null: false, default: 0
      add :consecutive_successes, :integer, null: false, default: 0
    end

    create constraint(:endpoints, :endpoints_valid_streaks,
             check:
               "consecutive_failures BETWEEN 0 AND 3 AND consecutive_successes BETWEEN 0 AND 2 AND (consecutive_failures = 0 OR consecutive_successes = 0)"
           )

    create table(:incidents) do
      add :endpoint_id, references(:endpoints, on_delete: :delete_all), null: false

      # Timestamps/categories survive future result retention; endpoint deletion removes everything.
      add :opened_check_id, references(:check_runs, type: :uuid, on_delete: :nilify_all)
      add :resolved_check_id, references(:check_runs, type: :uuid, on_delete: :nilify_all)
      add :opened_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :error_category, :text, null: false
    end

    create unique_index(:incidents, [:endpoint_id],
             where: "resolved_at IS NULL",
             name: :incidents_one_open_per_endpoint
           )

    create index(:incidents, [:endpoint_id, :opened_at])
    create index(:incidents, [:opened_check_id])
    create index(:incidents, [:resolved_check_id])

    create constraint(:incidents, :incidents_valid_resolution,
             check:
               "(resolved_at IS NULL AND resolved_check_id IS NULL) OR (resolved_at IS NOT NULL AND resolved_at >= opened_at)"
           )

    create constraint(:incidents, :incidents_safe_category,
             check:
               "error_category IN ('connection','tls','timeout','unexpected_status','blocked_destination','response_limit','protocol','internal')"
           )
  end
end
