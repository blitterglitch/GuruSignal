defmodule GuruSignal.Repo.Migrations.AddCheckRunRetentionIndex do
  use Ecto.Migration

  def change do
    create index(:check_runs, [:endpoint_id, :completed_at, :id],
             name: :check_runs_retention_index
           )
  end
end
