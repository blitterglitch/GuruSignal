defmodule GuruSignal.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GuruSignalWeb.Telemetry,
      GuruSignal.Repo,
      {DNSCluster, query: Application.get_env(:guru_signal, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GuruSignal.PubSub},
      GuruSignal.OwnerAccess,
      Supervisor.child_spec({Task.Supervisor, name: GuruSignal.HTTPTasks, max_children: 4},
        id: GuruSignal.HTTPTasks
      ),
      Supervisor.child_spec({Task.Supervisor, name: GuruSignal.CheckWorkers, max_children: 4},
        id: GuruSignal.CheckWorkers
      ),
      GuruSignal.Monitoring.Scheduler,
      GuruSignal.Monitoring.RetentionWorker,
      # Start a worker by calling: GuruSignal.Worker.start_link(arg)
      # {GuruSignal.Worker, arg},
      # Start to serve requests, typically the last entry
      GuruSignalWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GuruSignal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GuruSignalWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
