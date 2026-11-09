defmodule GuruSignal.Release do
  @moduledoc "Database release tasks, based on the Phoenix release template; no Mix or web startup."
  @app :guru_signal

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()

    unless repo in repos() and is_integer(version) and version >= 0,
      do:
        raise(ArgumentError, "expected a configured repository and nonnegative migration version")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    {:ok, _} = Application.ensure_all_started(:ssl)
    :ok = Application.ensure_loaded(@app)
  end
end
