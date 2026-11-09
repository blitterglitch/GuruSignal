import Config

config :guru_signal, :secure_cookies, true

# mix assets.deploy generates the digested asset manifest during image builds.
config :guru_signal, GuruSignalWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# Enforce HTTPS behind Fly Proxy; allow internal probes and local smoke tests.
# force_ssl is configured at compile time.
config :guru_signal, GuruSignalWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      paths: ["/health/live", "/health/ready"],
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

# Do not print debug messages in production
config :logger, level: :info

# Runtime secrets and connection settings are loaded in config/runtime.exs.
