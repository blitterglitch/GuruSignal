# Deployment

Guru Signal packages as an Elixir release in a multi-stage container. The builder
compiles locked dependencies and digested assets; the Debian runtime runs as
`nobody` under tini. It needs no Mix installation or database at image-build time.
Local credentials and development tooling are excluded by `.dockerignore`.

## Runtime configuration

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | Required PostgreSQL URL; percent-encode credentials |
| `DATABASE_SSL` | Defaults to `true`, with peer/hostname verification |
| `DATABASE_CA_CERT_FILE` | Optional CA file inside the container; requires TLS |
| `SECRET_KEY_BASE` | Required signing secret, at least 64 bytes |
| `OWNER_PASSWORD_HASH` | Owner credential; absent configuration disables login |
| `PHX_HOST` | Required public hostname |
| `PHX_BIND_IP`, `PORT` | Listen address and port; image defaults are `::` and `8080` |
| `POOL_SIZE`, `ECTO_IPV6` | Database pool size (default 10) and optional IPv6 sockets |
| `MONITORING_ENABLED` | Must be `true` to run production checks |
| `RETENTION_ENABLED`, `CHECK_RETENTION_DAYS` | Opt-in cleanup and retention window |

Configure database TLS through these variables, not `ssl`/`sslmode` URL query
parameters. Supply secrets at runtime. `/app/bin/server` starts the release with
HTTP enabled; `/app/bin/migrate` applies migrations without starting the scheduler
or web server. Server startup does not migrate automatically.

## Local container smoke test

On Linux with Podman, build the image and start local PostgreSQL:

```bash
podman build --tag guru-signal:local .
bash bin/dev-db start
bash bin/dev-db status
```

Wait for PostgreSQL to be healthy. Create a separate smoke database once:

```bash
podman exec guru-signal-postgres sh -c 'exec createdb -U "${POSTGRES_USER:-postgres}" guru_signal_release_smoke'
python3 bin/prepare-release-env
```

The helper writes ignored `.env.release.local` with private permissions, a new
signing key, loopback binding, and local database TLS disabled. It refuses to
overwrite an existing file; reuse it for subsequent runs. Monitoring and retention
stay disabled, and no owner hash is copied.

```bash
podman run --rm --network=host --env-file .env.release.local \
  guru-signal:local /app/bin/migrate
podman run --detach --name guru-signal-release-smoke --network=host \
  --env-file .env.release.local guru-signal:local
curl -i http://localhost:8080/health/live
curl -i http://localhost:8080/health/ready
podman stop guru-signal-release-smoke
podman rm guru-signal-release-smoke
```

Both probes should return 200 with `{"status":"ok"}`. This verifies packaging,
startup, and database connectivity; HTTPS login and outbound checks need separate
deployment verification. The smoke database remains for reuse.

## Fly.io configuration

[fly.trial.toml](../fly.trial.toml) records the configuration used for a completed
trial: one shared CPU / 1 GiB application Machine in Frankfurt, Fly Managed
Postgres, verified database TLS, and a readiness probe. The base images are pinned
by digest in that file. Review image compatibility when updating them.

Monitoring needs a running process, so automatic stopping is disabled. One-machine
deployment uses `--ha=false`; `min_machines_running = 1` alone is not a maximum.
Migrations run through the release command. The single-node design does not offer
high availability or uninterrupted checks during deploys and restarts.

For a new deployment, complete [local setup](setup.md), install flyctl, and sign in.
The secrets helper requires Python 3.11 or later. Provision an app and database,
then update `app` and `PHX_HOST` in the configuration. Creating these resources
incurs usage charges; review the account's current terms before proceeding. The secrets helper stages
`DATABASE_URL`, `OWNER_PASSWORD_HASH`, and `SECRET_KEY_BASE` through Fly's API; it
does not save production secrets locally. It expects a `direct.*.flympg.net` URL.
Direct connections keep application pooling and migrations on the same path.

```bash
fly config validate --strict --config fly.trial.toml
python3 bin/stage-fly-trial-secrets
fly deploy --config fly.trial.toml --ha=false
```

After deployment, verify both HTTPS health routes, owner login, endpoint editing,
check results, incident recovery, and cross-tab updates. Inspect Machine count
and logs. The original trial passed these checks and its app/database were removed;
there is no running public instance. Stopping an app does not stop database usage;
remove unneeded trial resources separately.

## Recovery

Inspect logs and database readiness before replacing a failing release. Keep the
previous image available and prefer additive migrations compatible with it. Revert
an image only after assessing schema compatibility; do not automatically roll back
migrations. `GuruSignal.Release.rollback/2` requires a repository and explicit
migration version, and may remove data.

A restart invalidates owner sessions and can leave pending checks until their
leases expire. Retention deletions require a backup to reverse. The trial verified
deployment, not backup restoration; establish and test a restore procedure before
using this setup for ongoing monitoring.
