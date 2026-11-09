# Public status page

Implemented at `/`. The owner ran formatting, compilation with warnings treated
as errors, and the asset build successfully. After fixing shared-topic test
assertions to match their own endpoint IDs, all 101 tests passed with seed
518359. The owner also confirmed the public browser workflow works correctly.
Four pure status-policy tests and isolated template rendering checks passed in
the coding sandbox; database and LiveView tests ran on the host.

## Public information

All endpoint names are public service labels, including paused endpoints. Use
names suitable for visitors; there is no per-service publication setting in this
MVP. The owner form explains this before saving.

`Monitoring.PublicStatus` selects and returns a restricted projection. Public
LiveView assigns contain only service IDs, names, states, check timestamps, and
incident IDs, service names, and opening/resolution timestamps. Endpoint URLs,
HTTP codes, expected codes, timeout/interval configuration, response durations,
error categories, check identifiers, and owner credentials are excluded.

The page has no administration actions or links to owner diagnostics. `/admin`
and its detail pages retain their HTTP and LiveView authentication. Public and
owner pages use separate LiveView sessions. The generated Phoenix welcome page
has been removed.

## State and freshness

- **Operational:** a fresh successful check for the current configuration, with
  no open incident.
- **Check failing:** a fresh failed check before an incident is confirmed.
- **Incident open:** an unresolved incident, including when checks become stale.
- **Recovering:** a fresh first success while the incident remains open.
- **Monitoring paused:** the owner disabled checks; this does not resolve an
  existing incident, which remains in the active-incident list.
- **Unknown:** no current-configuration result, a future-dated result, or an old
  result without an open incident.

A result becomes stale after its configured interval plus request timeout plus
10 seconds of dispatch allowance. The public LiveView refreshes every 30 seconds,
so aging may take up to another 30 seconds to appear. Check completions and
configuration changes refresh immediately through PubSub. A disconnected client
shows a connection-loss notice; without JavaScript, visitors must reload.

All active incidents are shown independently of the 20-entry recent incident
history limit. Times are UTC and mark confirming checks, not the first failure.
The page does not claim availability percentages or infer health from an absence
of incidents. Retention, pagination, and visitor rate limits remain future work.

## Verification

No migration or dependency change is needed. Stop the running server, then run:

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local assets.build
python3 bin/mix-local phx.server
```

Open `/` in a signed-out browser, and `/admin` in an owner session. Trigger checks
from the owner dashboard and watch public state and incident history update.
Pause or rename an endpoint and confirm the public page updates. Check that URLs,
HTTP codes, and failure categories appear only in the owner interface, and that
visiting `/admin` signed out redirects to login.

For a controlled incident/recovery test, start with
`MONITORING_ENABLED=false python3 bin/mix-local phx.server` and use the existing
[three-failure/two-success smoke test](incidents.md#host-verification). When manual
checks stop, a formerly operational service should become unknown after its
freshness budget and the next public refresh. Resume normal automatic monitoring
by restarting without that environment override.

Automated integration tests cover projection keys, configuration invalidation,
stale/pending results, the separate active-incident list, unauthenticated access,
read-only presentation, live recovery, edits, deletion, and periodic refresh.
