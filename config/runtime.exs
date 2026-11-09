import Config

# Load runtime secrets and settings; /app/bin/server enables HTTP in releases.
if System.get_env("PHX_SERVER") in ["true", "1"] do
  config :guru_signal, GuruSignalWeb.Endpoint, server: true
end

config :guru_signal, :owner_password_hash, System.get_env("OWNER_PASSWORD_HASH")

retention_days = String.to_integer(System.get_env("CHECK_RETENTION_DAYS", "30"))
unless retention_days in 1..3_650, do: raise("CHECK_RETENTION_DAYS must be 1..3650")

config :guru_signal,
  check_retention_days: retention_days,
  retention_enabled: config_env() != :test and System.get_env("RETENTION_ENABLED") == "true"

config :guru_signal,
       :monitoring_enabled,
       (config_env() == :dev and System.get_env("MONITORING_ENABLED", "true") == "true") or
         (config_env() == :prod and System.get_env("MONITORING_ENABLED") == "true")

config :guru_signal, GuruSignalWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() in [:dev, :test] do
  config :guru_signal, GuruSignal.Repo,
    username: System.get_env("POSTGRES_USER", "postgres"),
    password: System.fetch_env!("POSTGRES_PASSWORD")

  config :guru_signal, GuruSignalWeb.Endpoint,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :guru_signal, GuruSignalWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/guru_signal_web/router\.ex$"E,
        ~r"lib/guru_signal_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  database_uri = URI.new(database_url)

  unless match?(
           {:ok, %URI{scheme: scheme, host: host, path: path}}
           when scheme in ["ecto", "postgres", "postgresql"] and is_binary(host) and host != "" and
                  is_binary(path) and path != "/",
           database_uri
         ),
         do: raise("DATABASE_URL must contain a PostgreSQL host and database name")

  {:ok, database_uri} = database_uri

  unless Regex.match?(~r{\A/[^/]+\z}, database_uri.path),
    do: raise("DATABASE_URL must contain one database path segment")

  if Enum.any?(URI.query_decoder(database_uri.query || ""), fn {key, _} ->
       String.downcase(key) in ["ssl", "sslmode"]
     end),
     do: raise("Configure database TLS using DATABASE_SSL, not DATABASE_URL query parameters")

  ssl =
    case System.get_env("DATABASE_SSL", "true") do
      "true" -> true
      "false" -> false
      _ -> raise "DATABASE_SSL must be true or false"
    end

  ca_file = System.get_env("DATABASE_CA_CERT_FILE")
  if ca_file && not ssl, do: raise("DATABASE_CA_CERT_FILE requires DATABASE_SSL=true")
  ssl = if ca_file, do: [cacertfile: ca_file], else: ssl
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :guru_signal, GuruSignal.Repo,
    ssl: ssl,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # Supply a production signing key through secrets; bin/mix-local manages local keys.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  if byte_size(secret_key_base) < 64, do: raise("SECRET_KEY_BASE must be at least 64 bytes")

  host = System.get_env("PHX_HOST") || raise("PHX_HOST is required in production")
  if host == "", do: raise("PHX_HOST must not be empty")

  bind_ip =
    case :inet.parse_address(String.to_charlist(System.get_env("PHX_BIND_IP", "::"))) do
      {:ok, address} -> address
      _ -> raise "PHX_BIND_IP must be an IPv4 or IPv6 address"
    end

  config :guru_signal, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :guru_signal, GuruSignalWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: bind_ip
    ],
    secret_key_base: secret_key_base

  # Fly Proxy terminates public HTTPS; config/prod.exs enforces forwarded HTTPS.
end
