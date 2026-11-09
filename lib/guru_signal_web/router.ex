defmodule GuruSignalWeb.Router do
  use GuruSignalWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {GuruSignalWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :owner do
    plug(GuruSignalWeb.OwnerAuth)
  end

  scope "/health", GuruSignalWeb do
    pipe_through(:api)

    get("/live", HealthController, :live)
    get("/ready", HealthController, :ready)
  end

  scope "/", GuruSignalWeb do
    pipe_through(:browser)

    live_session :public do
      live("/", StatusLive)
    end

    get("/login", SessionController, :new)
    post("/login", SessionController, :create)
    delete("/logout", SessionController, :delete)
  end

  scope "/admin", GuruSignalWeb do
    pipe_through([:browser, :owner])

    live_session :owner, on_mount: [{GuruSignalWeb.OwnerAuth, :require_owner}] do
      live("/", AdminLive)
      live("/endpoints/:id", EndpointLive)
    end
  end

  # Compile diagnostics routes only for development.
  if Application.compile_env(:guru_signal, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: GuruSignalWeb.Telemetry)
    end
  end
end
