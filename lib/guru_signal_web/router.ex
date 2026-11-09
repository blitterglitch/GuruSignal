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

  scope "/", GuruSignalWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    get("/login", SessionController, :new)
    post("/login", SessionController, :create)
    delete("/logout", SessionController, :delete)
  end

  scope "/admin", GuruSignalWeb do
    pipe_through([:browser, :owner])

    live_session :owner, on_mount: [{GuruSignalWeb.OwnerAuth, :require_owner}] do
      live("/", AdminLive)
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", GuruSignalWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:guru_signal, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: GuruSignalWeb.Telemetry)
    end
  end
end
