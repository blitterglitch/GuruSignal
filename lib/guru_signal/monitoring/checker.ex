defmodule GuruSignal.Monitoring.Checker do
  @moduledoc "Runs DNS, destination authorization, and HTTP under one total deadline."
  alias GuruSignal.Monitoring.{Destination, DNSResolver, MintClient}

  def check(endpoint, opts \\ []) do
    started = System.monotonic_time(:millisecond)
    deadline = started + endpoint.timeout_ms
    resolver = Keyword.get(opts, :resolver, DNSResolver)
    client = Keyword.get(opts, :client, MintClient)
    supervisor = Keyword.get(opts, :task_supervisor, GuruSignal.HTTPTasks)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        try do
          with {:ok, target} <- Destination.resolve(endpoint.url, resolver) do
            client.fetch(target, deadline)
          end
        rescue
          _error -> {:error, :internal}
        end
      end)

    result =
      case Task.yield(task, max(deadline - System.monotonic_time(:millisecond), 0)) do
        {:ok, result} ->
          result

        {:exit, _reason} ->
          {:error, :internal}

        nil ->
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end

    duration = max(System.monotonic_time(:millisecond) - started, 0)
    result = if duration > endpoint.timeout_ms, do: {:error, :timeout}, else: result
    outcome(result, endpoint.expected_status, duration)
  end

  defp outcome({:ok, status}, expected, duration) when status >= 200 and status <= 599 do
    %{
      success: status == expected,
      http_status: status,
      duration_ms: duration,
      error_category: if(status == expected, do: nil, else: :unexpected_status)
    }
  end

  defp outcome({:error, reason}, _expected, duration)
       when reason in [
              :connection,
              :tls,
              :timeout,
              :blocked_destination,
              :response_limit,
              :protocol,
              :internal
            ] do
    %{success: false, http_status: nil, duration_ms: duration, error_category: reason}
  end

  defp outcome(_result, _expected, duration),
    do: %{success: false, http_status: nil, duration_ms: duration, error_category: :internal}
end
