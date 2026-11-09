defmodule GuruSignalWeb.EndpointLive do
  use GuruSignalWeb, :live_view

  import GuruSignalWeb.MonitoringPresentation
  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.{Checks, Incidents}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Monitoring.subscribe()
    {:ok, assign(socket, :endpoint, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket), do: {:noreply, refresh(socket, id)}

  @impl true
  def handle_info({event, id}, socket)
      when event in [:endpoint_changed, :check_completed, :history_pruned] do
    if socket.assigns.endpoint && socket.assigns.endpoint.id == id do
      {:noreply, refresh(socket, id)}
    else
      {:noreply, socket}
    end
  end

  defp refresh(socket, id) do
    case Monitoring.get_endpoint(id) do
      nil ->
        socket
        |> put_flash(:error, "Endpoint no longer exists.")
        |> push_navigate(to: ~p"/admin")

      endpoint ->
        checks = Checks.recent_for(endpoint.id)
        incidents = Incidents.recent_for(endpoint.id)
        open = Enum.find(incidents, &is_nil(&1.resolved_at))
        latest = if run = List.first(checks), do: %{endpoint.id => run}, else: %{}
        open_by_endpoint = if open, do: %{endpoint.id => open}, else: %{}

        socket
        |> assign(:page_title, endpoint.name)
        |> assign(:endpoint, endpoint)
        |> assign(:checks, checks)
        |> assign(:incidents, incidents)
        |> assign(:status, status_label(endpoint, latest, open_by_endpoint))
        |> assign(:last_check, current_check(endpoint, latest))
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="main-content" tabindex="-1" class="mx-auto max-w-5xl px-6 py-10 space-y-8">
      <header class="flex flex-wrap items-center justify-between gap-4">
        <.link navigate={~p"/admin"} class="underline">Back to dashboard</.link>
        <.link href={~p"/logout"} method="delete" class="underline">Sign out</.link>
      </header>
      <Layouts.flash_group flash={@flash} />
      <div :if={@endpoint} id="endpoint-detail" class="space-y-8">
        <section aria-labelledby="endpoint-heading">
          <h1 id="endpoint-heading" class="text-2xl font-semibold">{@endpoint.name}</h1>
          <p
            id="endpoint-status"
            role="status"
            aria-live="polite"
            aria-atomic="true"
            class="mt-2 font-semibold"
          >
            {@status}
          </p>
          <p class="mt-2 break-all font-mono text-sm">{@endpoint.url}</p>
          <dl class="mt-4 flex flex-wrap gap-6 text-sm">
            <div>
              <dt class="font-semibold">Expected HTTP status</dt><dd>{@endpoint.expected_status}</dd>
            </div>
            <div>
              <dt class="font-semibold">Check interval</dt><dd>
                {@endpoint.interval_seconds} seconds
              </dd>
            </div>
            <div>
              <dt class="font-semibold">Request timeout</dt><dd>{@endpoint.timeout_ms} ms</dd>
            </div>
          </dl>
          <p :if={@last_check} id="latest-check" class="mt-4">
            Last check:
            <time datetime={DateTime.to_iso8601(@last_check.checked_at)}>{DateTime.to_iso8601(
              @last_check.checked_at
            )}</time>
            · {@last_check.duration_ms} ms · HTTP {@last_check.http_status || "—"} · {error_label(
              @last_check.error_category
            )}
          </p>
          <p :if={is_nil(@last_check)} class="mt-4">
            No completed check for the current configuration.
          </p>
          <p :if={not @endpoint.enabled} class="mt-2">
            Monitoring is paused. Existing incidents remain open until recovery is confirmed.
          </p>
        </section>

        <section aria-labelledby="check-history-heading">
          <h2 id="check-history-heading" class="text-xl font-semibold">Recent check results</h2>
          <p class="mt-2 text-sm">
            Up to 50 completed checks, newest sequence first. History includes previous configurations. Times are UTC; durations include DNS and connection setup through final response headers.
          </p>
          <p :if={@checks == []} id="empty-check-history" class="mt-4">No completed checks yet.</p>
          <div :if={@checks != []} class="mt-4 overflow-x-auto">
            <table id="endpoint-checks" class="table">
              <caption class="sr-only">Recent completed checks for this endpoint</caption>
              <thead>
                <tr>
                  <th scope="col">Check</th><th scope="col">Configuration</th><th scope="col">
                    Checked at (UTC)
                  </th><th scope="col">Result</th><th scope="col">HTTP</th><th scope="col">
                    Expected
                  </th><th scope="col">Time</th><th scope="col">Category</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={run <- @checks} id={"check-#{run.id}"}>
                  <th scope="row">#{run.sequence}</th>
                  <td>
                    v{run.endpoint_version}{if run.endpoint_version == @endpoint.lock_version,
                      do: " (current)",
                      else: " (previous)"}
                  </td>
                  <td>
                    <time datetime={DateTime.to_iso8601(run.checked_at)}>{DateTime.to_iso8601(
                      run.checked_at
                    )}</time>
                  </td>
                  <td>{if run.success, do: "Success", else: "Failure"}</td>
                  <td>{run.http_status || "—"}</td><td>{run.expected_status}</td><td>
                    {run.duration_ms} ms
                  </td><td>{error_label(run.error_category)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section aria-labelledby="incident-timeline-heading">
          <h2 id="incident-timeline-heading" class="text-xl font-semibold">Incident timeline</h2>
          <p class="mt-2 text-sm">
            Up to 20 incidents, newest first. Opening and resolution times mark the checks that confirmed each transition.
          </p>
          <p :if={@incidents == []} id="empty-incident-timeline" class="mt-4">
            No incidents recorded.
          </p>
          <ol id="incident-timeline" class="mt-4 space-y-4">
            <li
              :for={incident <- @incidents}
              id={"incident-#{incident.id}"}
              class="rounded-lg border border-base-300 p-4"
            >
              <h3 class="font-semibold">
                Incident #{incident.id} · {if incident.resolved_at, do: "Resolved", else: "Open"}
              </h3>
              <p>
                Opened
                <time datetime={DateTime.to_iso8601(incident.opened_at)}>{DateTime.to_iso8601(
                  incident.opened_at
                )}</time>
                · {error_label(incident.error_category)}
              </p>
              <p :if={incident.resolved_at}>
                Resolved
                <time datetime={DateTime.to_iso8601(incident.resolved_at)}>{DateTime.to_iso8601(
                  incident.resolved_at
                )}</time>
              </p>
              <p :if={is_nil(incident.resolved_at)}>
                Recovery requires two consecutive successful checks.
              </p>
            </li>
          </ol>
        </section>
      </div>
    </main>
    """
  end
end
