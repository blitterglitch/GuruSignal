# Health checks and continuous integration

Implemented. The owner verified formatting, compilation with warnings treated
as errors, the full suite (110 passed with seed 459195), and the asset build.
Both health endpoints returned HTTP 200 with status `ok` in the running app.
Three focused tests also passed in the coding sandbox; workflow YAML, action
pins, permissions, database settings, and shell syntax passed local checks.
The owner also reported a successful GitHub Actions run with three dependency
deprecation warnings, described below.

## Health endpoints

| Route | Meaning | Response |
| --- | --- | --- |
| `GET /health/live` | The web process can serve a request; does not query PostgreSQL. | `200 {"status":"ok"}` |
| `GET /health/ready` | PostgreSQL accepts a small `SELECT 1` through the application's repository. | `200 {"status":"ok"}` or `503 {"status":"unavailable"}` |

Both are public JSON routes with `Cache-Control: no-store`, without browser
sessions or owner authentication. Query logging is disabled for the readiness
probe, and failures are normalized without returning exception or database
connection details. The query uses a 1,000 ms timeout. Neither endpoint calls a
monitored service or changes monitoring state.

Readiness verifies connectivity, not migrations, scheduler progress, owner
credential configuration, or monitored-service health. A failing monitored service
must not make the application fail its own platform health check. Liveness can
remain successful during a database outage, while readiness returns 503.

Production HTTPS enforcement excludes only the two health paths in addition to
its existing localhost exclusions. This permits platform probes over HTTP;
ordinary public-host routes still redirect to HTTPS. A test exercises the actual
production SSL configuration. Fly configuration will use `/health/ready` when
we prepare deployment; no Fly resources or health-check settings were created.

## CI workflow

`.github/workflows/ci.yml` runs for pushes to `main`, pull requests, and manual
dispatch. It uses Ubuntu 24.04, Elixir 1.20.5 compiled for OTP 29, OTP 29.1.2, and
a PostgreSQL 17.11 service container. These match the verified local runtime and
PostgreSQL helper. The workflow:

1. Checks out source and installs the pinned runtime.
2. Generates and masks an ephemeral signing key.
3. Fetches dependencies with `mix deps.get --check-locked` and compiles them.
4. Checks formatting and compiles application code with warnings treated as errors.
5. Runs `mix test`; the existing test alias creates and migrates the test database.
6. Installs the standard asset binaries and builds assets.

CI uses ordinary Mix and disposable environment settings. It does not load
`.env.postgres`, local owner hashes, or persistent signing keys via `mix-local`.
The database password in YAML is only for the disposable service container;
production credentials are not needed. Automatic outbound monitoring is disabled.
Tests use simulated or loopback fixtures rather than public monitored services.
Dependency and asset installation still require network access.

Dependency compilation runs separately so known upstream warnings remain visible;
application compilation treats warnings as errors. No additional static-analysis
tool or production release build is claimed by this workflow.

The first successful remote run reported three instances of the deprecated
`xref: [exclude: ...]` configuration. The installed `postgrex`, `phoenix_ecto`,
and `phoenix_live_dashboard` dependencies still use it in their own `mix.exs`
files; GuruSignal's `mix.exs` does not. Elixir currently translates that option
to `elixirc_options: [no_warn_undefined: ...]` and emits a warning. Keep the
warnings visible and address them through upstream dependency updates rather
than editing fetched dependency files.

Actions are pinned to verified commit IDs, repository-token access is read-only,
and checkout does not retain credentials. Runs have a 15-minute limit; a newer
run cancels an older run for the same ref. Review action pins when updating them.
The workflow does not deploy, publish artifacts, or modify the repository.

The owner pushed the workflow and reported its first successful remote run.
The agent did not push or dispatch it. No CI badge has been added.
Review any account-specific Actions usage limits before running it.

## Local verification

No migration or dependency change is required. Run:

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local assets.build
python3 bin/mix-local phx.server
```

In another terminal, check the HTTP status, headers, and body:

```bash
curl -i http://localhost:4000/health/live
curl -i http://localhost:4000/health/ready
```

Both should return HTTP 200 and `{"status":"ok"}` while PostgreSQL is available.
Tests cover generic readiness failure and database-independent liveness using a
process-local unavailable repository, without stopping the development database.

## References consulted

- [GitHub PostgreSQL service containers](https://docs.github.com/en/actions/tutorials/use-containerized-services/create-postgresql-service-containers)
- [setup-beam runtime installation and strict versions](https://github.com/erlef/setup-beam/blob/main/README.md)
- [Pinned setup-beam action inputs](https://github.com/erlef/setup-beam/blob/54075bcc5e249e4758d363f27d099f55d843f124/action.yml)
- [Pinned checkout release](https://github.com/actions/checkout/commit/3d3c42e5aac5ba805825da76410c181273ba90b1)
- [Ecto SQL queries](https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.html#query/4)

The installed Plug.SSL and DBConnection source was also checked for path
exclusions and query timeouts.
