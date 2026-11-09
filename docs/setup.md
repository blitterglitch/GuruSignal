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

## Planned scaffolding after access is restored

Keep tool installation local to the project rather than altering the global Mix
archive directory. Ignore these directories before installing:

```gitignore
/.local-tools/
/.hex/
/.env
/.env.*
!/.env.example
```

From the project root, the intended commands are:

```bash
export MIX_HOME="$PWD/.local-tools/mix"
export MIX_ARCHIVES="$MIX_HOME/archives"
export HEX_HOME="$PWD/.hex"
mix local.hex --force
mix archive.install hex phx_new 1.8.16 --force
mix phx.new . --app guru_signal --module GuruSignal --database postgres --no-install
```

Review generator prompts carefully: preserve the existing README and design
documents. Review the generated dependency requirements before resolving them.
Use the standard LiveView and asset defaults. The generator may create its own
agent guidance; inspect it before implementation. Ignore local tool/cache paths
in the generated `.gitignore` as well.

After database configuration, the milestone acceptance commands will be:

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix assets.setup
mix assets.build
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

These are intended steps, not passing checks. No Phoenix source or dependency
lockfile exists yet. PostgreSQL/HTTP-client compatibility remains to be verified
through actual dependency resolution, compilation, and tests.

Fly CLI installation, license selection, cloud resources, and deployment can wait
until the local application is verified. Ask for approval before cloud creation
or spending; do not run `fly launch` now.
