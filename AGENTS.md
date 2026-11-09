# Repository Guidelines

## Project Structure & Module Organization

GuruSignal is currently a planning-only repository: `README.md` tracks scope and
progress; `docs/architecture.md` describes the proposed design; `docs/setup.md`
records initial environment findings. Recheck those findings before relying on them.

After Phoenix scaffolding, use `lib/guru_signal/` for domain contexts,
`lib/guru_signal_web/` for controllers, components, and LiveViews,
`priv/repo/migrations/` for migrations, `assets/` for frontend assets, and `test/`
for tests mirroring source paths. Generate directly in this repository.

## Build, Test, and Development Commands

No `mix.exs` exists yet. After scaffolding and configuring PostgreSQL:

- `mix deps.get` — fetch dependencies.
- `mix ecto.create` and `mix ecto.migrate` — create databases and apply migrations.
- `mix assets.setup` and `mix assets.build` — install asset tools and build assets.
- `mix phx.server` — run the local application.
- `mix format --check-formatted` — check formatting; use `mix format` to fix it.
- `mix compile --warnings-as-errors` — compile and reject warnings.
- `mix test` — run ExUnit tests; append a test path for focused checks.

Use PostgreSQL 17 in Podman with persistent local storage. The intended production
setup is Fly Machines with Fly Managed Postgres, subject to cost approval.

## Coding Style & Naming Conventions

Use two-space indentation and standard Elixir formatting. Name modules
`GuruSignal.Monitoring.Endpoint`, files `endpoint.ex`, and functions/variables
`snake_case`. Keep incident rules in domain code and network calls outside web
processes. Prefer focused modules and standard Phoenix assets. No additional
linter has been selected.

## Testing Guidelines

Use ExUnit, Ecto database tests, and focused LiveView tests. Name files
`*_test.exs` and describe observable behavior. Test three-failure opening,
two-success recovery, duplicate/stale results, concurrency, authentication, and
SSRF boundaries. Inject HTTP/DNS boundaries; tests must not depend on public
Internet services. No coverage percentage is required.

## Commit & Pull Request Guidelines

There are no commits yet, so no historical convention exists. Use small milestone
commits with imperative subjects, such as `Add endpoint validation`. PRs should
explain the problem, resulting behavior, validation performed, and limitations.
Link relevant issues and include screenshots for UI changes. Do not claim checks
passed unless executed.

## Security & Agent Instructions

Never commit secrets or response bodies. Enforce request-time destination checks,
validated-IP connections, disabled redirects, and bounded requests. Protect admin
routes and LiveView mounts. Keep public diagnostics restricted.

Do not push, create external resources, or incur cloud costs without explicit
approval. Obtain approval before selecting a license. Explain new Elixir concepts
briefly and document agent assistance honestly.
