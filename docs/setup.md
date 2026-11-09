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
| Repository | Empty workspace; `.git` is empty and read-only; Git reports no repository |
| Dependency access | `curl -I --connect-timeout 10 https://repo.hex.pm` fails DNS resolution |

No applicable ancestor or repository `AGENTS.md` was found. No global tools were
changed. No cloud resources, commits, pushes, or deployment were performed.

## Required environment changes

The coding environment needs outbound DNS/HTTPS access to GitHub, Hex, and Phoenix
asset download hosts, writable repository metadata, and access to PostgreSQL.
Changing the app cannot resolve these execution-environment restrictions.

Restore or clone the actual repository using the host environment before resuming.
This workspace now contains planning documents: preserve them when bringing in the
repository. Do not delete or replace the mounted `.git` directory from this session.

## Local PostgreSQL option for Fedora

Run these on the host, not inside the restricted coding environment. The package
and service commands change system state and have not been executed here:

```bash
sudo dnf install postgresql-server postgresql-contrib
```

Only for a **new, uninitialized** PostgreSQL installation:

```bash
sudo postgresql-setup --initdb --unit postgresql
```

Start the server and create a development-only role (the password prompt keeps
the password out of shell history):

```bash
sudo systemctl enable --now postgresql
sudo -u postgres createuser --createdb --pwprompt guru_signal
psql -h 127.0.0.1 -U guru_signal -d postgres -W -c 'SELECT version();'
```

Use an existing role/database instead if already configured. Ensure localhost
connections use SCRAM password authentication; do not weaken authentication to
`trust`. The development role needs database creation for Ecto's dev/test setup;
production will use separately scoped credentials. Supply the local connection
through an ignored environment file or interactive environment settings once
runtime configuration exists. Never commit its password.

Reference: [Fedora PostgreSQL guide](https://docs.fedoraproject.org/en-US/quick-docs/postgresql/).
The documentation fetch was blocked by the site's access challenge during this
session, so the commands above have not been verified against that live page.

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
