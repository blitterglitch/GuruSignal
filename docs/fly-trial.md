# Completed Fly.io trial deployment

Approved by the owner for the limited trial below. The owner validated the TOML
and created Managed Postgres cluster `9g6y30wx4g6ov5ml`. The owner deployed app
`guru-signal` and verified both HTTPS health routes returned HTTP 200 with status
`ok` at 2026-11-09 20:41 UTC. The owner verified one healthy 1 GB app Machine in
`fra` (ID `83dd004b7319d8`) and reported the browser features working after the
Edit focus correction was redeployed. The owner subsequently confirmed removal
of the trial app and Managed Postgres cluster. There is no active demo deployment.
The owner found that Edit displayed an empty Name field. The cause was client
focus occurring before the form patch; the local fix now pushes a focus event
after the patch. The owner redeployed and confirmed that editing now works.
`fly.trial.toml` is separate from the default `fly.toml` so
commands must explicitly select this trial configuration. A separate writable
CLI configuration directory permits local CLI help checks, but the sandbox
blocks DNS/network access to `api.fly.io`. Provisioning must run on the owner's
host. No token or secret should be pasted into chat.

## Trial scope

The owner confirmed organization `personal` (display name `blitterglitch`) and
requires trial-only use: no credit card, payment method, or paid upgrade.
The owner reports $1 credit, unused, expiring November 15, 2026. Current official
trial rules apply that credit to the signup personal organization and permit
Machines and Managed Postgres. Without a credit card, trial Machines stop after
five minutes. This is a temporary deployment/verification exercise, not continuous
monitoring. The app's autostop setting cannot override the platform trial limit.
Adding a card lifts trial restrictions and permits billing beyond remaining credit;
this proposal does not authorize adding a card or upgrading to paid usage.

Proposed resources:

- App name `guru-signal`, matching the owner's local TOML edit, one shared CPU / 1 GB app
  Machine in Frankfurt (`fra`), plus a short-lived migration Machine.
- One Basic Managed Postgres cluster in Frankfurt, PostgreSQL 17, no extensions,
  with its own empty database and a five-connection application pool.
- Shared public IP configuration only; no dedicated IPv4, app volume, replicas,
  extra app Machine, or custom domain.
- Monitoring enabled for verification, retention disabled, owner authentication
  and verified database TLS retained. No development data or credentials imported.

The app and database region match. The trial config disables request-idle stopping,
but the five-minute trial stop still applies. Deploy with `--ha=false`; the minimum
Machine setting does not cap Machine count. Verify actual resources after creation.
Single-Machine restarts interrupt monitoring and revoke owner sessions; this remains
a single-node application with deliberately accepted downtime.

## Cost and cleanup boundary

Pricing checked November 9, 2026:

| Resource | Published monthly baseline |
| --- | --- |
| Frankfurt shared-CPU / 1 GB app Machine, 30 days continuous | $7.73 |
| Managed Postgres Basic | $38.00 |
| Managed Postgres storage | $0.28 per GB used / 30 days |

At those rates, one hour of continuous app/database compute and 10 GB storage
usage is approximately $0.067 before tax, migration-Machine runtime, network,
and any other account usage. This is an illustration, not a reserved price or
hard spending cap. The trial stop can reduce app runtime; the database remains
a separately managed resource. A whole month is incompatible with the $1 budget.

Limit the first verification session to one hour and watch the Billing dashboard.
Destroy the disposable cluster and app immediately afterward; stopping/deleting
only the web Machine does not delete Managed Postgres. Trial expiry is not the
cleanup plan. Confirm the dashboard has no leftover clusters, Machines, or volumes.
Do not put valuable data in this trial database.

## Approval and execution sequence

Before running any mutating CLI command, the owner must approve the resource scope
and brief trial session above. The owner explicitly approved this scope, including
creation and teardown, for organization `personal`, with no credit card or paid
upgrade. This does not authorize additional resources or ongoing paid operation.
If Fly requests a payment method, stop rather than upgrade.

After approval:

Preflight on the host before provisioning:

```bash
fly config validate --strict --config fly.trial.toml
podman image inspect docker.io/library/elixir:1.20.5-otp-29-slim --format '{{index .RepoDigests 0}}'
podman image inspect docker.io/library/debian:trixie-slim --format '{{index .RepoDigests 0}}'
```

The image digests are public identifiers and can be reviewed without sharing
credentials. The owner supplied the digests for the locally smoke-tested Elixir
and Debian images; both are now pinned in `[build.args]` in `fly.trial.toml`.
The installed CLI
supports `--pg-major-version 17`; do not rely on its default, which is 16.

1. Confirm the app name is available, the selected organization is the credit's
   personal organization, the credit remains available, and the plan is Basic.
2. Review/pin image digests for the locally verified builder and runner before
   the remote build; retain the matching Debian/runtime pair.
3. Create only the proposed app and one Basic PostgreSQL 17 cluster in `fra`.
   Confirm pricing in the creation flow; stop if it differs from the approved scope.
4. Obtain the **direct** database URL privately from the cluster's Connect tab.
   For this one-node trial, use that URL for both the Ecto pool and migration;
   this avoids PgBouncer session-lock/prepared-statement differences. The runtime
   requires TLS configuration outside the URL's query string. Verify its
   certificate chain/hostname; do not disable verification to get a green check.
5. Generate a separate production signing key and provision the owner password
   hash. Stage `DATABASE_URL`, `SECRET_KEY_BASE`, and `OWNER_PASSWORD_HASH` as
   secrets through standard input/a private ignored file. Do not paste secrets
   into chat, command arguments, Git, or `fly.trial.toml`. Avoid an automatic
   database attach/restart before all required secrets are ready.
6. Deploy using `fly deploy --config fly.trial.toml --ha=false`. The migration
   command runs before updating the app. Verify only one app Machine exists.
7. Test HTTPS health probes, signed-out public access, owner login, a manual
   check, live updates, and the three-failure/two-success incident sequence using
   **Check now** to fit the short trial runtime. Check that URLs/diagnostics stay
   owner-only. Observe at least one scheduled check while the Machine is running.
8. Record the deployment result and account usage, then destroy only these newly
   created disposable resources. Verify cleanup in the dashboard. Any destructive
   command must target the exact IDs created for this approved trial.

The owner validated the configuration with flyctl and deployed the app. HTTPS
liveness/readiness probes pass against the release configured with verified
database TLS. Machine count and owner/public workflows were verified by the owner.
The owner confirmed teardown; no independent database TLS handshake trace was captured.
A successful trial does not establish a continuously available portfolio demo.

## Stage and deploy the provisioned trial

From this cluster's Connect tab, copy the direct connection URL privately, then run:

```bash
python3 bin/stage-fly-trial-secrets
fly deploy --config fly.trial.toml --ha=false
```

The helper privately prompts for the direct database URL and a new trial owner
password, hashes that password locally, generates a separate signing key, and
stages all three secrets using Fly's standard input. It writes no secret file
and starts no deployment. Re-running it rotates the signing key/password for the
next deploy. Do not share its inputs or run it through shell tracing.
Paste the full `postgresql://...` URL from Connect → Direct; the prompt hides it.
The helper accepts surrounding quotes and standard secure TLS query options,
then removes those options because the app separately requires verified TLS.
Invalid-input messages identify the issue without echoing the connection string.

After deployment, verify both HTTPS health routes and owner/public behavior, then
remove cluster `9g6y30wx4g6ov5ml` and app `guru-signal` after the approved brief test.
Provisioning has started the trial's database usage clock; keep the session short.

## Approved teardown

The owner confirmed completion of the following teardown and verification steps.
These commands are retained as a record, not a request to run them again.

After the successful trial, remove exactly these approved disposable resources:

```bash
fly apps destroy guru-signal --yes
fly mpg destroy 9g6y30wx4g6ov5ml --yes
```

This permanently removes the trial app and database, including their test data.
The managed cluster requires its own deletion command. Verify both are absent
from the personal organization's resource lists and check Billing for remaining
credit/other resources. No development database or local Podman volume is targeted.

## Sources

- [Fly trial credit, limits, and five-minute stopping](https://docs.fly.io/about/free-trial)
- [Resource pricing and Frankfurt example](https://docs.fly.io/about/pricing)
- [Managed Postgres plans and storage](https://docs.fly.io/postgres)
- [Managed Postgres connection guidance](https://docs.fly.io/postgres/client-configuration)
- [Fly app configuration](https://docs.fly.io/reference/configuration)
- [Deployment options, including HA default](https://docs.fly.io/flyctl/cmd/fly_deploy)
- [Cost management and separate managed-service cleanup](https://docs.fly.io/about/cost-management)
