# Repository Guidelines

## Project Structure

Guru Signal is a single-owner Phoenix application for learning Elixir and operating
on Fly.io. Keep the scope small and the documentation accurate. Use “Guru Signal”
in prose; preserve code identifiers such as `GuruSignal.Monitoring.Endpoint`.

- `lib/guru_signal/`: domain contexts, monitoring workers, and owner sessions.
- `lib/guru_signal_web/`: controllers, components, LiveViews, and authentication.
- `priv/repo/migrations/`: schema changes and database constraints.
- `assets/`: CSS and JavaScript; `artwork/`: banner assets and provenance.
- `test/`: ExUnit tests mirroring source paths.
- `docs/`: setup, architecture, security, operations, testing, and deployment.

## Development Commands

Follow [local setup](docs/setup.md) first. Use PostgreSQL 17 in Podman and wait for
`bash bin/dev-db status` to report `running healthy`.

- `python3 bin/mix-local setup`: fetch dependencies, migrate, and build assets.
- `python3 bin/mix-local phx.server`: start the development server.
- `python3 bin/mix-local ecto.migrate`: apply migrations.
- `python3 bin/mix-local format --check-formatted`: verify formatting; omit the flag to apply it.
- `python3 bin/mix-local compile --warnings-as-errors`: compile application code strictly.
- `python3 bin/mix-local test`: run tests; append a path or `--seed` to focus a run.
- `python3 bin/mix-local assets.build`: build CSS and JavaScript.

The helper loads ignored local configuration and forwards standard Mix commands.

## Coding and Testing

Use two-space indentation, standard Elixir formatting, `snake_case` filenames and
functions, and descriptive modules such as `GuruSignal.Monitoring.Endpoint`.
Keep incident rules in domain code and network calls outside web processes and
database transactions. Preserve the single-node deployment assumptions.

Name tests `*_test.exs` and describe observable behavior. Cover incident thresholds,
stale/duplicate results, concurrency, authentication, and SSRF boundaries. Inject
HTTP/DNS dependencies; tests must not rely on public Internet services. No coverage
percentage is required. Report only checks actually executed.

## Commits and Pull Requests

Use focused changes and imperative subjects, such as `Add endpoint validation`.
The user performs commits: provide commands and wait for confirmation before
continuing to the next milestone. PRs should explain behavior, validation, and
limitations; link relevant issues and include screenshots for UI changes.

## Security and Agent Instructions

Never commit secrets or response bodies. Preserve destination validation,
validated-IP connections, disabled redirects, bounded requests, protected admin
routes, and restricted public diagnostics.

Do not push, create external resources, or incur cloud costs without explicit
approval. Obtain approval before selecting a license. Explain new Elixir concepts
briefly and keep assistance disclosures factual and concise.
