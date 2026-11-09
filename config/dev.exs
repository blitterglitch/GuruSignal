import Config

# Configure your database
config :guru_signal, GuruSignal.Repo,
  hostname: "127.0.0.1",
  database: "guru_signal_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: false,
  pool_size: 10

# Enable code reloading and asset watchers for local development.
config :guru_signal, GuruSignalWeb.Endpoint,
  # Keep the development server accessible only from this machine.
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:guru_signal, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:guru_signal, ~w(--watch)]}
  ]

# Expose LiveDashboard only in development.
config :guru_signal, dev_routes: true

# Keep safe check identifiers/categories visible in development logs.
config :logger, :default_formatter, format: "[$level] $message $metadata\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true
