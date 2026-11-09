defmodule GuruSignalWeb.MonitoringPresentation do
  @moduledoc "Shared owner-facing status and safe check category labels."

  def current_check(endpoint, latest) do
    case Map.get(latest, endpoint.id) do
      %{endpoint_version: version} = run when version == endpoint.lock_version -> run
      _ -> nil
    end
  end

  def status_label(%{enabled: false}, _latest, _open), do: "Paused"

  def status_label(endpoint, latest, open) do
    cond do
      Map.has_key?(open, endpoint.id) and endpoint.consecutive_successes == 1 ->
        "Recovering (1/2 successes)"

      Map.has_key?(open, endpoint.id) ->
        "Incident open"

      is_nil(current_check(endpoint, latest)) ->
        "Awaiting check"

      current_check(endpoint, latest).success ->
        "Healthy"

      endpoint.consecutive_failures == 0 ->
        "Awaiting confirmation"

      true ->
        "Failing (#{endpoint.consecutive_failures}/3 failures)"
    end
  end

  def error_label(nil), do: "—"
  def error_label(:connection), do: "Connection / DNS failure"
  def error_label(:tls), do: "TLS failure"
  def error_label(:timeout), do: "Request timeout"
  def error_label(:unexpected_status), do: "Unexpected HTTP status"
  def error_label(:blocked_destination), do: "Destination blocked"
  def error_label(:response_limit), do: "Response limit exceeded"
  def error_label(:protocol), do: "Invalid HTTP response"
  def error_label(:internal), do: "Check could not complete"
end
