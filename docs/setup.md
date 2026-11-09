# Local setup

## Prerequisites

The tested environment uses Elixir 1.20.5, Erlang/OTP 29.1.2, and PostgreSQL 17.
Install Elixir/OTP, Git, Python 3, Podman, and OpenSSL. OpenSSL is used to generate
local TLS test certificates. Phoenix downloads its Tailwind and esbuild binaries;
Node.js is not required for the standard asset build.

## Start PostgreSQL

```bash
cp .env.example .env.postgres
```

Replace the placeholder password before starting the container. Use literal
`KEY=value` entries without shell quotes; the helpers do not evaluate shell syntax.
The file is ignored by Git.

```bash
bash bin/dev-db start
bash bin/dev-db status
```

Wait for `running healthy`. PostgreSQL listens on `127.0.0.1:5432` and keeps data
in the `guru-signal-postgres-data` Podman volume. Credentials in `.env.postgres`
initialize an empty volume; editing them later does not change existing database
roles or passwords. The application creates separate development and test databases.

## Initialize and run

```bash
python3 bin/mix-local local.hex --force
python3 bin/mix-local local.rebar --force
python3 bin/mix-local setup
python3 bin/set-owner-password
python3 bin/mix-local phx.server
```

`setup` fetches dependencies, creates and migrates the development database, and
builds assets. The password helper prompts without echoing input and requires at
least 16 characters. Restart the server after changing the owner password.

| Route | Purpose |
| --- | --- |
| `/` | Public service status and incident history |
| `/login` | Owner sign-in |
| `/admin` | Protected monitoring dashboard |
| `/admin/endpoints/:id` | Protected endpoint history |
| `/health/live`, `/health/ready` | Health probes |
| `/dev/dashboard` | Development-only diagnostics |

## Local configuration

`bin/mix-local` loads PostgreSQL credentials, a persistent signing key, and the
owner password hash, then forwards arguments to standard Mix. It supports only
development and test environments. Secrets and local tool state live in ignored
`.env.postgres`, `.local-tools/`, and `.hex/`; keep them private.

The signing key protects session integrity. The owner password is separate from
the PostgreSQL password. Owner sessions are held in memory, so restarting the
application signs users out.

## Everyday commands

```bash
bash bin/dev-db start   # Start again after a reboot
bash bin/dev-db status
bash bin/dev-db psql    # Open the PostgreSQL console
bash bin/dev-db logs
bash bin/dev-db stop    # Preserve the database volume
python3 bin/mix-local ecto.migrate
```

A connection-refused error at `127.0.0.1:5432` usually means PostgreSQL is stopped
or still starting. Start it and wait for a healthy status before running tests.
See [testing](testing.md) for the verification commands.
