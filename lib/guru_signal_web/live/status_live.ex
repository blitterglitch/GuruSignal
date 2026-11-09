defmodule GuruSignalWeb.StatusLive do
  use GuruSignalWeb, :live_view
  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.PublicStatus

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Monitoring.subscribe()
      schedule_refresh()
    end

    {:ok, socket |> assign(:page_title, "Service status") |> refresh()}
  end

  @impl true
  def handle_info({event, _id}, socket) when event in [:endpoint_changed, :check_completed],
    do: {:noreply, refresh(socket)}

  def handle_info(:refresh_status, socket) do
    schedule_refresh()
    {:noreply, refresh(socket)}
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh_status, 30_000)
  defp refresh(socket), do: assign(socket, PublicStatus.snapshot())

  defp state_label(:operational), do: "Operational"
  defp state_label(:degraded), do: "Check failing"
  defp state_label(:incident), do: "Incident open"
  defp state_label(:recovering), do: "Recovering"
  defp state_label(:paused), do: "Monitoring paused"
  defp state_label(:unknown), do: "Unknown — awaiting a fresh check"

  defp state_class(state) when state in [:incident, :degraded], do: "border-error"
  defp state_class(:recovering), do: "border-warning"
  defp state_class(_state), do: "border-base-300"

  @impl true
  def render(assigns) do
    ~H"""
    <main id="main-content" tabindex="-1" class="mx-auto max-w-5xl px-6 py-10 space-y-8">
      <header class="border-4 border-error p-6">
        <p class="font-mono text-sm">Guru Signal</p>
        <h1 class="mt-2 text-3xl font-semibold">Service status</h1>
        <p class="mt-3">Less meditation. More remediation.</p>
      </header>
      <p
        id="public-connection-status"
        role="status"
        hidden
        phx-disconnected={JS.show(to: "#public-connection-status") |> JS.remove_attribute("hidden")}
        phx-connected={JS.hide(to: "#public-connection-status") |> JS.set_attribute({"hidden", ""})}
        class="rounded-lg border border-warning p-4"
      >
        Connection lost. Displayed status may be out of date; reconnecting…
      </p>
      <noscript>Live updates require JavaScript. Reload this page to fetch current status.</noscript>

      <section aria-labelledby="services-heading">
        <h2 id="services-heading" class="text-xl font-semibold">Services</h2>
        <p class="mt-2 text-sm">Updates arrive automatically while connected. Times are UTC.</p>
        <p :if={@services == []} id="empty-services" class="mt-4">No services are listed yet.</p>
        <ul id="public-services" class="mt-4 space-y-4">
          <li
            :for={service <- @services}
            id={"service-#{service.id}"}
            class={["rounded-lg border p-5", state_class(service.state)]}
          >
            <h3 class="font-semibold">{service.name}</h3>
            <p role="status" aria-live="polite" aria-atomic="true" class="mt-2">
              <span class="sr-only">{service.name}: </span>{state_label(service.state)}
            </p>
            <p :if={service.checked_at} class="mt-2 text-sm">
              Last checked
              <time datetime={DateTime.to_iso8601(service.checked_at)}>{DateTime.to_iso8601(
                service.checked_at
              )}</time>
            </p>
          </li>
        </ul>
        <p class="mt-4 text-sm">
          An incident opens after three consecutive failed checks and resolves after two consecutive successful checks. A failing check may appear before an incident is confirmed. Paused or missing checks do not establish service health.
        </p>
      </section>

      <section aria-labelledby="active-incidents-heading">
        <h2 id="active-incidents-heading" class="text-xl font-semibold">
          Active incidents ({length(@active_incidents)})
        </h2>
        <p :if={@active_incidents == []} id="no-active-incidents" class="mt-3">
          No active incidents recorded. See individual services for current check coverage.
        </p>
        <ul class="mt-4 space-y-3">
          <li
            :for={incident <- @active_incidents}
            id={"public-active-incident-#{incident.id}"}
            class="rounded-lg border border-error p-4"
          >
            <h3 class="font-semibold">{incident.name} · Incident #{incident.id}</h3>
            <p>
              Opened
              <time datetime={DateTime.to_iso8601(incident.opened_at)}>{DateTime.to_iso8601(
                incident.opened_at
              )}</time>
            </p>
          </li>
        </ul>
      </section>

      <section aria-labelledby="incident-history-heading">
        <h2 id="incident-history-heading" class="text-xl font-semibold">Incident history</h2>
        <p class="mt-2 text-sm">
          The 20 most recent incidents. Times mark the checks that confirmed opening or recovery.
        </p>
        <p :if={@recent_incidents == []} id="empty-public-history" class="mt-3">
          No incidents recorded.
        </p>
        <ol id="public-incident-history" class="mt-4 space-y-3">
          <li
            :for={incident <- @recent_incidents}
            id={"public-incident-#{incident.id}"}
            class="rounded-lg border border-base-300 p-4"
          >
            <h3 class="font-semibold">
              {incident.name} · Incident #{incident.id} · {if incident.resolved_at,
                do: "Resolved",
                else: "Open"}
            </h3>
            <p>
              Opened
              <time datetime={DateTime.to_iso8601(incident.opened_at)}>{DateTime.to_iso8601(
                incident.opened_at
              )}</time>
            </p>
            <p :if={incident.resolved_at}>
              Resolved
              <time datetime={DateTime.to_iso8601(incident.resolved_at)}>{DateTime.to_iso8601(
                incident.resolved_at
              )}</time>
            </p>
          </li>
        </ol>
      </section>
    </main>
    """
  end
end
