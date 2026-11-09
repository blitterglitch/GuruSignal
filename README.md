<img src="artwork/guru-signal/guru-signal-banner.png" alt="Guru Signal — Less meditation. More remediation." width="100%">

# Guru Signal

Real-time endpoint monitoring and incident tracking, built with Phoenix LiveView.

Guru Signal checks HTTP services, tracks failures, and publishes a live status page.
It a project built to learn Elixir, OTP, Phoenix, and application operations on Fly.io.
Its deliberately small scope emphasizes reliable checks, safe outbound requests, and clear incident state.

## Features

- Manage endpoints, pause monitoring, and trigger checks from a protected dashboard.
- Open incidents after three consecutive failures; resolve them after two successes.
- Inspect check history and incident timelines, with live updates across browser tabs.
- Publish service status without exposing URLs or private diagnostics.
- Validate outbound destinations at request time, including DNS and IPv6 restrictions.
- Expose health probes, structured logs, Telemetry events, and optional history cleanup.

The interface takes its name and visual cues from the Amiga's Guru Meditation
error. Notifications, teams, content assertions, and multi-region monitoring are
outside the current scope.

## Run locally

Use Elixir 1.20.5 / OTP 29.1.2, Python 3, Git, and Podman. PostgreSQL 17 runs in a
local container.
Follow [local setup](docs/setup.md) for first-time dependency installation.

```bash
cp .env.example .env.postgres
# Set a development password in .env.postgres before continuing.
bash bin/dev-db start
bash bin/dev-db status  # Wait for: running healthy
python3 bin/mix-local local.hex --force
python3 bin/mix-local local.rebar --force
python3 bin/mix-local setup
python3 bin/set-owner-password
python3 bin/mix-local phx.server
```

Open `http://localhost:4000` for public status or `/login` for administration.
`bin/mix-local` loads ignored local credentials and forwards commands to Mix.

## Design

A Phoenix monolith combines LiveView, Ecto, PostgreSQL, and supervised OTP workers.
Network checks run outside database transactions and web processes. PostgreSQL
claims, configuration versions, and row locks prevent duplicate or stale results
from changing incident state. PubSub refreshes connected views after commits.

The deployment target is one application Machine in one region. A temporary Fly.io
trial with Fly Managed Postgres was deployed and verified, then removed. There is
currently no live demo. The release and Fly configuration document this deployment;
high availability is outside the project scope.

## Development

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local assets.build
```

[GitHub Actions](.github/workflows/ci.yml) runs these checks against PostgreSQL.
Tests cover incident rules, concurrent updates, authentication, SSRF boundaries,
and LiveView behavior without relying on public Internet services.

## Documentation

- [Local setup](docs/setup.md): prerequisites, credentials, and everyday commands.
- [Architecture](docs/architecture.md): data flow, consistency, and design trade-offs.
- [Security](docs/security.md): threat model, access control, and public data boundaries.
- [Operations](docs/operations.md): health checks, observability, and retention.
- [Testing](docs/testing.md): verification commands, coverage, and CI.
- [Deployment](docs/deployment.md): releases, Fly configuration, and recovery.

## Development notes

Codex assisted with research, scaffolding, implementation, and review. The author
remained responsible for requirements, design decisions, validation, and the result.

## License

Original code and documentation are licensed under [MIT](LICENSE).
Third-party materials retain their own terms; the Amiga-derived banner images are
excluded. See [third-party notices](THIRD_PARTY_NOTICES.md).
