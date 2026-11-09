# Environment and prerequisite handoff

Inspected on 2026-11-09 in `/home/dawid/edu/elixir/guru-signal`.

| Item | Observed |
| --- | --- |
| OS | Fedora Linux 44 |
| Elixir | 1.20.5, compiled for OTP 29 |
| Erlang/OTP | 29.1.2 |
| Mix / Hex | 1.20.5 / 2.7.0 |
| Git | 2.56.0 |
| Phoenix generator | Not installed |
| PostgreSQL server/client | Not found on PATH |
| Podman | Present, but initialization fails on read-only `/run/user/1000/libpod` |
| Fly CLI | Not found on PATH; not needed until deployment preparation |
| Repository | Initialized on `main`; origin is `git@github.com:blitterglitch/GuruSignal.git`; sandbox Git metadata remains read-only |
| Dependency access | `curl -I --connect-timeout 10 https://repo.hex.pm` fails DNS resolution |

The initial inspection found no contributor instructions; `AGENTS.md` has since
been added. The owner committed the initial documentation and contributor guide
from the host terminal. Agents must stop at commit milestones and ask the owner
to execute the commit commands. No global tools or cloud resources were changed.

## Required environment changes

The coding environment needs outbound DNS/HTTPS access to GitHub, Hex, and Phoenix
asset download hosts, writable repository metadata, and access to PostgreSQL.
Changing the app cannot resolve these execution-environment restrictions.

The repository is now initialized and attached to GitHub. Git metadata remains
read-only inside the coding sandbox; the owner handles commits on the host.

## Local PostgreSQL with Podman

Run from this repository on the host, where rootless Podman works:

```bash
cp .env.example .env.postgres
chmod 600 .env.postgres
```

Edit `.env.postgres` and replace the password placeholder with a unique local
password. Keep the supplied `POSTGRES_USER=postgres` and `POSTGRES_DB=postgres`;
the helper's health check and SQL shell use these names. The file is ignored by
Git. Do not source it as shell code. Podman reads it using `--env-file`.

```bash
bash bin/dev-db start
bash bin/dev-db status
```

Initialization takes a few seconds. Repeat `status` until it reports
`running healthy`. To verify the server:

```bash
podman exec guru-signal-postgres psql -U postgres -d postgres -c 'SELECT version();'
```

The helper uses `docker.io/library/postgres:17.11-bookworm`, a PostgreSQL 17
image matching the intended production major version. The tag pins the minor
version for repeatability but is not an immutable digest; review patch updates
regularly. Its named volume `guru-signal-postgres-data` stores data at
`/var/lib/postgresql/data`. Port 5432 is published only on `127.0.0.1`.
No host PostgreSQL installation or Compose provider is required.

Other commands:

```bash
bash bin/dev-db logs
bash bin/dev-db psql
bash bin/dev-db stop
```

Stopping preserves data. Starting an existing container reuses its configuration.
Changing the environment file does not rotate a database password: image
initialization variables apply only to an empty volume. The development user is
a superuser for Ecto database creation; use separately scoped production roles.
If port 5432 is occupied, resolve the conflict before starting the container.
Do not delete the named volume unless its development data can be discarded.

The container's local SQL shell checks initialization. Host TCP password
connectivity will be verified through Ecto after scaffolding. Configure Ecto to
use `127.0.0.1`, port 5432, and the password from the ignored file; that runtime
configuration has not been implemented yet.

References: [official PostgreSQL image](https://hub.docker.com/_/postgres) and
[Podman run options](https://docs.podman.io/en/latest/markdown/podman-run.1.html).
The helper has passed shell syntax checks. The owner ran it on the host and
reported `running healthy` from `bash bin/dev-db status`. Container startup
remains blocked inside the coding session by read-only Podman runtime storage.
Host TCP password connectivity through Ecto is still pending scaffolding.

## Phoenix skeleton and local commands

The owner generated Phoenix 1.8.16 directly in this repository with PostgreSQL,
LiveView, and standard assets, without the mailer or automatic dependency
installation. Existing documentation, contributor guidance, and ignore rules
were preserved. The owner subsequently verified the commands below on the host.

Use the local helper from the project root (requires Python 3):

```bash
python3 bin/mix-local deps.get
python3 bin/mix-local local.rebar --force
python3 bin/mix-local ecto.create
python3 bin/mix-local ecto.migrate
python3 bin/mix-local assets.setup
python3 bin/mix-local assets.build
python3 bin/mix-local format --check-formatted
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local phx.server
```

Open <http://localhost:4000> after starting the server. Stop with Ctrl+C (twice
if needed). Linux live reload may require `inotify-tools` on the host.

`bin/mix-local` loads recognized settings from `.env.postgres` as literal values,
without shell evaluation or quote removal. Use `KEY=value` without surrounding
quotes; environment variables take precedence. It sets project-local Mix and Hex
paths and creates an ignored, owner-readable `.local-tools/secret_key_base` on
first use. The key persists so development sessions survive server restarts.
Development and test use it; production requires its own `SECRET_KEY_BASE`.
Session and LiveView signing salts are public purpose labels, not secret keys.

Development uses `guru_signal_dev`; tests use `guru_signal_test` plus an optional
`MIX_TEST_PARTITION` suffix. `POSTGRES_DB=postgres` initializes the server's
bootstrap database; it does not override these application database names. Ecto
creates them using the development superuser. Database tests run in Ecto's SQL
Sandbox, which rolls test changes back to isolate cases.

Plain `mix` commands also work if the needed environment variables are supplied
explicitly. Runtime database configuration requires `POSTGRES_PASSWORD` and
`SECRET_KEY_BASE` for development/test. The helper rejects production mode; use
release configuration and deployment secrets for production.

Inside the coding sandbox, `deps.get` currently fails with Mix's TCP-backed
filesystem lock error (`:eperm`), in addition to the previously observed network
restrictions. Run dependency/build/database checks on the host and report their
results. The owner supplied successful output for dependency resolution, database
creation, migrations (none pending), asset installation/build, formatting, and
`compile --warnings-as-errors`. ExUnit reported **5 passed** for the generated
skeleton. These tests do not validate monitoring features, which are not built yet.
Browser startup verification is still pending. Commit the generated `mix.lock`.

### Dependency warnings observed

During first compilation in development and test under Elixir 1.20.5 / OTP 29,
Gettext 1.0.2 emitted redundant-clause/type warnings and a deprecation warning for
`Kernel.ParallelCompiler.async/1`. DNSCluster 0.2.0 emitted a disjoint-type
comparison warning. Dependencies also emitted warnings about deprecated
`xref: [exclude: ...]` project settings; these occur in dependency `mix.exs` files,
not the GuruSignal project configuration.

No warnings were reported while compiling GuruSignal's own modules, and the
owner's subsequent `compile --warnings-as-errors` command passed. This does not
mean that a fresh compilation of all dependencies is warning-free. Keep the
warnings visible and review upstream updates; do not edit downloaded dependency
files or add global warning suppression. No dependency overrides were introduced.

Fly CLI installation, license selection, cloud resources, and deployment can wait
until the local application is verified. Ask for approval before cloud creation
or spending; do not run `fly launch` now.
