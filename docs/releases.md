# Production release and local container verification

Verified locally by the owner: 130 host tests passed, and the container smoke
procedure completed with both liveness and database-readiness probes successful.
Three production-configuration tests also passed in the coding sandbox, as did
isolated checks for the local environment helper. Release source compiles without
warnings, overlay scripts pass shell syntax checks, and `git diff --check` passes.
Podman verification ran on the host because it cannot run in the coding sandbox.
Production deployment and real database TLS verification remain pending.

## Packaging

The Dockerfile follows the installed Phoenix 1.8 release template. Its builder
uses the official `elixir:1.20.5-otp-29-slim` image and checks for the verified
Elixir 1.20.5 / OTP 29.1.2 pair. The final Debian trixie image contains the release,
CA roots, runtime libraries, and tini, and runs as `nobody`. It serves port 8080.
Dependencies and digested/minified assets are built inside the builder; development
Mix dependencies and build tools are not copied to the runtime image.

The release bundles Erlang/Elixir and the compiled application. `rel/overlays/bin`
supplies standard-style `server` and `migrate` commands. The runtime does not need
Mix installed. Erlang distribution is disabled for this single-node image; remote
shell/RPC commands are not part of this setup.

`.dockerignore` excludes local credentials, signing keys, downloaded dependencies,
Git metadata, development build output, certificates, and other local tooling.
No production secrets are build arguments or baked into application configuration.

Builder/runner tags were checked against the official image sources. They are
still mutable tags, not verified digest pins. A changed builder runtime fails the
version guard. Before deployment, review image/platform digests and update both
`BUILDER_IMAGE` and `RUNNER_IMAGE` build arguments together, preserving compatible
Debian versions. Package updates and native-library compatibility require an
actual build/run check; source inspection is insufficient.

## Runtime configuration

| Variable | Meaning |
| --- | --- |
| `DATABASE_URL` | Required PostgreSQL URL; percent-encode credentials. |
| `DATABASE_SSL` | Defaults to `true`, using Postgrex peer/hostname verification. Explicit `false` is used only for the local plaintext smoke database here. |
| `DATABASE_CA_CERT_FILE` | Optional readable CA file path in the runtime container; requires TLS enabled. |
| `SECRET_KEY_BASE` | Required, at least 64 bytes; supply through runtime secrets. |
| `PHX_HOST` | Required public hostname; `localhost` for the smoke test. |
| `PHX_BIND_IP` | Listen address; defaults to IPv6 wildcard `::`. Smoke testing uses `127.0.0.1`. |
| `PORT` | Image defaults to 8080. |
| `POOL_SIZE` | Defaults to 10; smoke testing uses 2. |
| `OWNER_PASSWORD_HASH` | Provision the owner hash through runtime secrets before testing administration. Missing configuration keeps login unavailable. |
| `MONITORING_ENABLED` | Production monitoring starts only with `true`. |
| `RETENTION_ENABLED` | Cleanup starts only with `true`; review the [retention policy](retention.md). |
| `ECTO_IPV6` | Enables IPv6 PostgreSQL socket options when the deployment requires it. |

`DATABASE_URL` must not contain `ssl`/`sslmode` query parameters: use the explicit
TLS variables above to avoid Ecto URL options silently overriding the TLS policy.
A provider connection URL may need adapting. Custom CA paths refer to mounted
runtime files, not host files automatically visible inside the container.

HTTPS enforcement and Secure cookies remain enabled in production. Only health
paths and existing localhost exemptions bypass HTTPS redirects. Validate proxy
header trust and real HTTPS login during deployment; local HTTP probes cannot
verify that behavior.

## Host checks and image build

First run the regular checks:

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
```

Then build on your Linux host with Podman:

```bash
podman build --tag guru-signal:local .
```

The build fetches public images/packages/dependencies and assembles a production
release. It needs no database or production secrets. The existing CI workflow
checks the test environment and assets; it does not yet build this image.

## Isolated local smoke test

Keep the development PostgreSQL container running. Create a separate empty smoke
database; run the creation command once (an existing-database error means it was
already created):

```bash
bash bin/dev-db start
podman exec guru-signal-postgres sh -c 'exec createdb -U "${POSTGRES_USER:-postgres}" guru_signal_release_smoke'
python3 bin/prepare-release-env
```

The helper reads `.env.postgres` literally and writes ignored `.env.release.local`
with mode 0600, percent-encoded local credentials, a new signing key, and loopback
binding. It refuses to overwrite an existing file. It does not create the database,
run the image, copy the owner hash, or enable monitoring/cleanup.

Migrate that database using the release, then start the container:

```bash
podman run --rm --network=host --env-file .env.release.local \
  guru-signal:local /app/bin/migrate

podman run --detach --name guru-signal-release-smoke --network=host \
  --env-file .env.release.local guru-signal:local

curl -i http://localhost:8080/health/live
curl -i http://localhost:8080/health/ready
podman logs --tail 50 guru-signal-release-smoke
```

This host-network recipe is for Linux Podman and uses a loopback-only app binding;
there is no port publication or remote service creation. Port 8080 must be free.
Both probes should return HTTP 200 with `{"status":"ok"}`. Database readiness
checks the actual release connection to the smoke database. Run `migrate` again
to verify that applying already-applied migrations is harmless.

The smoke environment has no owner hash and deliberately keeps monitoring and
retention disabled. It validates packaging, startup, and database connectivity;
it does not validate production TLS, owner login over HTTPS, outbound monitoring,
or real deployment behavior. Do not point it at production credentials/data.

Stop and remove the smoke container afterward:

```bash
podman stop guru-signal-release-smoke
podman rm guru-signal-release-smoke
```

The separate database remains available for another smoke test. Its credentials
and signing key remain in the ignored local environment file; keep it private.
No development database is dropped or cleaned by these commands.

## Migrations, recovery, and remaining deployment work

The server command does not migrate automatically. Run `/app/bin/migrate` as a
separate pre-start/release step with the same database configuration. It loads
application configuration and starts the repository via Ecto.Migrator, without
starting the web endpoint, scheduler, or retention worker. Migration failure must
block starting a newly deployed version.

A template-style `GuruSignal.Release.rollback/2` helper is available for a configured
repository and an explicit nonnegative migration version. Do not automatically
roll back schemas when reverting an image. Assess compatibility and backups first;
rolling back migrations can delete data, and retention deletions require a backup
for restoration. Prefer additive migrations compatible with the previous release.

Before Fly deployment, review app name/region, one-machine/no-autostop scheduling,
Managed Postgres connection details and verified TLS, secrets, backup/restore,
image digests, proxy trust, health checks, owner HTTPS login, and cost. No `fly.toml`,
registry push, Fly app, database service, or billable resource has been created.
Those operations require the owner's explicit approval.

## Sources

- [Phoenix 1.8 releases guide](https://phoenix.hexdocs.pm/releases.html) and installed `phx.gen.release` templates.
- [Official Elixir image manifest](https://github.com/docker-library/official-images/blob/master/library/elixir).
- [Verified Elixir builder source](https://github.com/erlef/docker-elixir/blob/0e268c530b10333abe30aa249aeb22beef8bb464/1.20/slim/Dockerfile).
- [Erlang 29 slim base source](https://github.com/erlang/docker-erlang-otp/blob/master/29/slim/Dockerfile).
- Installed Postgrex 0.22.4 documentation/source for secure TLS defaults, and Ecto repository URL precedence.
