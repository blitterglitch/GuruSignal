defmodule GuruSignalWeb.AdminLive do
  use GuruSignalWeb, :live_view

  import GuruSignalWeb.MonitoringPresentation

  alias GuruSignal.Monitoring
  alias GuruSignal.Monitoring.Endpoint
  alias GuruSignal.Monitoring.{CheckRunner, Checks, Incidents}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Monitoring.subscribe()

    {:ok,
     socket
     |> refresh()
     |> assign(:page_title, "Endpoint administration")
     |> assign(:monitoring_enabled, Application.get_env(:guru_signal, :monitoring_enabled, false))
     |> reset_form()}
  end

  @impl true
  def handle_event("new", _params, socket), do: {:noreply, reset_form(socket)}

  def handle_event("edit", %{"id" => id}, socket) do
    case Monitoring.get_endpoint(id) do
      nil ->
        {:noreply, missing_endpoint(socket)}

      endpoint ->
        {:noreply,
         socket
         |> assign(:editing, endpoint)
         |> assign(:form, to_form(Monitoring.change_endpoint(endpoint)))}
    end
  end

  def handle_event("validate", %{"endpoint" => attrs}, socket) do
    changeset =
      socket.assigns.editing
      |> Monitoring.change_endpoint(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"endpoint" => attrs}, socket) do
    editing = socket.assigns.editing

    result =
      if editing.id do
        Monitoring.update_endpoint(editing, attrs)
      else
        Monitoring.create_endpoint(attrs)
      end

    case result do
      {:ok, _endpoint} ->
        message = if editing.id, do: "Endpoint updated.", else: "Endpoint created."
        {:noreply, socket |> refresh() |> reset_form() |> put_flash(:info, message)}

      {:error, changeset} ->
        if Keyword.has_key?(changeset.errors, :lock_version) do
          {:noreply, stale_endpoint(socket)}
        else
          {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    case Monitoring.get_endpoint(id) do
      nil ->
        {:noreply, missing_endpoint(socket)}

      endpoint ->
        case Monitoring.update_endpoint(endpoint, %{enabled: not endpoint.enabled}) do
          {:ok, updated} ->
            message = if updated.enabled, do: "Endpoint enabled.", else: "Endpoint paused."
            {:noreply, socket |> refresh() |> put_flash(:info, message)}

          {:error, _changeset} ->
            {:noreply, stale_endpoint(socket)}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Monitoring.get_endpoint(id) do
      nil ->
        {:noreply, missing_endpoint(socket)}

      endpoint ->
        case Monitoring.delete_endpoint(endpoint) do
          {:ok, deleted} ->
            socket =
              if socket.assigns.editing.id == deleted.id, do: reset_form(socket), else: socket

            {:noreply, socket |> refresh() |> put_flash(:info, "Endpoint deleted.")}

          {:error, _changeset} ->
            {:noreply, stale_endpoint(socket)}
        end
    end
  end

  def handle_event("check", %{"id" => id}, socket) do
    case Monitoring.get_endpoint(id) do
      nil ->
        {:noreply, missing_endpoint(socket)}

      %{enabled: false} ->
        {:noreply, put_flash(socket, :error, "Enable the endpoint before checking it.")}

      endpoint ->
        case CheckRunner.enqueue(endpoint.id) do
          {:ok, _pid} ->
            {:noreply, put_flash(socket, :info, "Check requested. Results update automatically.")}

          {:error, _reason} ->
            {:noreply,
             put_flash(socket, :error, "All check workers are busy. Try again shortly.")}
        end
    end
  end

  @impl true
  def handle_info({:endpoint_changed, _id}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:check_completed, _id}, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    endpoints = Monitoring.list_endpoints()
    incidents = Incidents.active()

    socket
    |> assign(:endpoints, endpoints)
    |> assign(:latest_checks, Checks.latest_for(endpoints))
    |> assign(:recent_checks, Checks.recent())
    |> assign(:active_incidents, incidents)
    |> assign(:open_by_endpoint, Map.new(incidents, &{&1.endpoint_id, &1}))
    |> assign(:recent_incidents, Incidents.recent())
  end

  defp reset_form(socket) do
    endpoint = %Endpoint{}

    socket
    |> assign(:editing, endpoint)
    |> assign(:form, to_form(Monitoring.change_endpoint(endpoint)))
  end

  defp missing_endpoint(socket) do
    socket |> refresh() |> reset_form() |> put_flash(:error, "Endpoint no longer exists.")
  end

  defp stale_endpoint(socket) do
    socket
    |> refresh()
    |> reset_form()
    |> put_flash(
      :error,
      "Endpoint changed in another session. Select Edit to load the latest version."
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="main-content" tabindex="-1" class="mx-auto max-w-5xl px-6 py-10 space-y-8">
      <header class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold">GuruSignal administration</h1>
          <p class="mt-2">Configure your monitored endpoints.</p>
          <.link href={~p"/"} class="mt-2 inline-block underline">Public status page</.link>
        </div>
        <.link href={~p"/logout"} method="delete" class="underline">Sign out</.link>
      </header>

      <Layouts.flash_group flash={@flash} />
      <p class="rounded-lg border border-base-300 p-4">
        <span :if={@monitoring_enabled}>Enabled endpoints are checked automatically.</span>
        <span :if={not @monitoring_enabled}>Automatic checks are paused; use Check now to run an enabled endpoint on demand.</span>
        Redirects are not followed.
        Response time includes DNS and connection setup through receipt of final response headers.
        Incidents open after three consecutive failures and resolve after two consecutive successes.
      </p>

      <section id="active-incidents" aria-labelledby="active-incidents-heading">
        <h2 id="active-incidents-heading" class="text-xl font-semibold">
          Active incidents ({length(@active_incidents)})
        </h2>
        <p :if={@active_incidents == []} class="mt-3">No active incidents.</p>
        <ul class="mt-4 space-y-3">
          <li
            :for={incident <- @active_incidents}
            id={"active-incident-#{incident.id}"}
            class="rounded-lg border border-error p-4"
          >
            <h3 class="font-semibold">
              {incident.endpoint.name} <span class="font-mono">#{incident.id}</span>
            </h3>
            <p>
              Opened
              <time datetime={DateTime.to_iso8601(incident.opened_at)}>{DateTime.to_iso8601(
                incident.opened_at
              )}</time>
              · {error_label(incident.error_category)}
            </p>
            <p :if={not incident.endpoint.enabled} class="mt-2">
              Monitoring paused; this incident remains open.
            </p>
          </li>
        </ul>
      </section>

      <section aria-labelledby="endpoint-editor-heading" class="rounded-lg border border-base-300 p-6">
        <h2 id="endpoint-editor-heading" class="text-xl font-semibold">
          {if @editing.id, do: "Edit endpoint", else: "Add endpoint"}
        </h2>
        <.form for={@form} id="endpoint-form" phx-change="validate" phx-submit="save" class="mt-4">
          <p
            :if={@form.source.action in [:insert, :update] and @form.errors != []}
            id="endpoint-form-errors"
            role="alert"
            class="mb-4 text-error"
          >
            Could not save the endpoint. Review the fields marked with errors below.
          </p>
          <div class="grid gap-x-6 sm:grid-cols-2">
            <.input field={@form[:name]} label="Name" required maxlength="100" />
            <.input
              field={@form[:url]}
              type="url"
              label="URL"
              required
              maxlength="2048"
              placeholder="https://example.com/health"
            />
            <.input
              field={@form[:expected_status]}
              type="number"
              label="Expected HTTP status"
              required
              min="200"
              max="599"
            />
            <.input
              field={@form[:interval_seconds]}
              type="select"
              label="Check interval"
              options={[{"60 seconds", 60}, {"5 minutes", 300}, {"15 minutes", 900}]}
            />
            <.input
              field={@form[:timeout_ms]}
              type="number"
              label="Request timeout (milliseconds)"
              required
              min="1000"
              max="10000"
            />
          </div>
          <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
          <p class="mb-4 text-sm">
            Endpoint names are displayed publicly on the status page. Use public service labels.
            HTTP port 80 or HTTPS port 443 only. No URL credentials or fragments.
          </p>
          <div class="flex gap-3">
            <button type="submit" class="btn btn-primary" phx-disable-with="Saving…">
              {if @editing.id, do: "Save changes", else: "Create endpoint"}
            </button>
            <button :if={@editing.id} type="button" phx-click="new" class="btn btn-ghost">Cancel edit</button>
          </div>
        </.form>
      </section>

      <section aria-labelledby="endpoints-heading">
        <h2 id="endpoints-heading" class="text-xl font-semibold">Endpoints ({length(@endpoints)})</h2>
        <p :if={@endpoints == []} id="empty-endpoints" class="mt-4">
          No endpoints yet. Add your first endpoint above.
        </p>
        <ul id="endpoints" class="mt-4 space-y-4">
          <li
            :for={endpoint <- @endpoints}
            id={"endpoint-#{endpoint.id}"}
            class="rounded-lg border border-base-300 p-5"
          >
            <div class="flex flex-wrap justify-between gap-3">
              <h3 class="font-semibold">
                <.link navigate={~p"/admin/endpoints/#{endpoint.id}"} class="underline">{endpoint.name}</.link>
              </h3>
              <span role="status" aria-live="polite" aria-atomic="true">
                <span class="sr-only">{endpoint.name}: </span>{status_label(
                  endpoint,
                  @latest_checks,
                  @open_by_endpoint
                )}
              </span>
            </div>
            <p class="mt-2 break-all font-mono text-sm">{endpoint.url}</p>
            <a
              :if={incident = @open_by_endpoint[endpoint.id]}
              href={"#active-incident-#{incident.id}"}
              class="mt-2 inline-block font-mono underline"
            >Incident #{incident.id}</a>
            <dl class="mt-3 flex flex-wrap gap-6 text-sm">
              <div>
                <dt class="font-semibold">Expected status</dt><dd>{endpoint.expected_status}</dd>
              </div>
              <div>
                <dt class="font-semibold">Interval</dt><dd>{endpoint.interval_seconds} seconds</dd>
              </div>
              <div>
                <dt class="font-semibold">Timeout</dt><dd>{endpoint.timeout_ms} ms</dd>
              </div>
            </dl>
            <div :if={run = current_check(endpoint, @latest_checks)} class="mt-3 text-sm">
              Last check:
              <time datetime={DateTime.to_iso8601(run.checked_at)}>{DateTime.to_iso8601(
                run.checked_at
              )}</time>
              · {run.duration_ms} ms · HTTP {run.http_status || "—"} · {error_label(
                run.error_category
              )}
            </div>
            <div class="mt-4 flex flex-wrap gap-3">
              <button
                type="button"
                phx-click="check"
                phx-value-id={endpoint.id}
                disabled={not endpoint.enabled}
                class="btn btn-sm"
                aria-label={"Check #{endpoint.name} now"}
              >Check now</button>
              <button
                id={"edit-endpoint-#{endpoint.id}"}
                type="button"
                phx-click={
                  JS.push("edit", value: %{id: endpoint.id}) |> JS.focus(to: "#endpoint_name")
                }
                aria-label={"Edit #{endpoint.name}"}
                class="btn btn-sm"
              >Edit</button>
              <button
                id={"toggle-endpoint-#{endpoint.id}"}
                type="button"
                phx-click="toggle"
                phx-value-id={endpoint.id}
                aria-label={"#{if endpoint.enabled, do: "Pause", else: "Enable"} #{endpoint.name}"}
                class="btn btn-sm"
              >
                {if endpoint.enabled, do: "Pause", else: "Enable"}
              </button>
              <button
                id={"delete-endpoint-#{endpoint.id}"}
                type="button"
                phx-click="delete"
                phx-value-id={endpoint.id}
                aria-label={"Delete #{endpoint.name}"}
                data-confirm="Delete this endpoint and its check/incident history? This cannot be undone."
                class="btn btn-sm btn-error btn-outline"
              >Delete</button>
            </div>
          </li>
        </ul>
      </section>

      <section aria-labelledby="recent-checks-heading">
        <h2 id="recent-checks-heading" class="text-xl font-semibold">Recent checks</h2>
        <p :if={@recent_checks == []} class="mt-4">No completed checks yet.</p>
        <div :if={@recent_checks != []} class="mt-4 overflow-x-auto">
          <table id="recent-checks" class="table">
            <caption class="sr-only">The twenty most recent completed checks, newest first</caption>
            <thead>
              <tr>
                <th scope="col">Endpoint</th><th scope="col">Checked at (UTC)</th><th scope="col">
                  Result
                </th><th scope="col">HTTP</th><th scope="col">Expected</th><th scope="col">Time</th><th scope="col">
                  Category
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={run <- @recent_checks} id={"check-#{run.id}"}>
                <th scope="row">{run.endpoint.name}</th>
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

      <section aria-labelledby="incident-history-heading">
        <h2 id="incident-history-heading" class="text-xl font-semibold">Incident history</h2>
        <p :if={@recent_incidents == []} class="mt-3">No incidents recorded.</p>
        <div :if={@recent_incidents != []} class="mt-4 overflow-x-auto">
          <table id="incident-history" class="table">
            <caption class="sr-only">The twenty most recent incidents, newest first</caption>
            <thead>
              <tr>
                <th scope="col">Incident</th><th scope="col">Endpoint</th><th scope="col">
                  Opened (UTC)
                </th><th scope="col">Resolved (UTC)</th><th scope="col">Opening category</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={incident <- @recent_incidents} id={"incident-history-#{incident.id}"}>
                <th scope="row" class="font-mono">#{incident.id}</th><td>{incident.endpoint.name}</td>
                <td>
                  <time datetime={DateTime.to_iso8601(incident.opened_at)}>{DateTime.to_iso8601(
                    incident.opened_at
                  )}</time>
                </td>
                <td>
                  <time
                    :if={incident.resolved_at}
                    datetime={DateTime.to_iso8601(incident.resolved_at)}
                  >{DateTime.to_iso8601(incident.resolved_at)}</time><span :if={
                    is_nil(incident.resolved_at)
                  }>Open</span>
                </td>
                <td>{error_label(incident.error_category)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </main>
    """
  end
end
