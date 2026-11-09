# Operations

## Health checks

| Route | Behavior |
| --- | --- |
| `/health/live` | HTTP 200 with `{"status":"ok"}` when the web process responds |
| `/health/ready` | Runs `SELECT 1`; returns 200 on success or 503 with `{"status":"unavailable"}` |

Readiness uses a one-second database-query timeout and does not expose connection
errors. Both responses disable caching. These probes do not verify scheduler
progress, migrations, owner credentials, or external monitored services.

```bash
curl -i http://localhost:4000/health/live
curl -i http://localhost:4000/health/ready
```

## Logs and metrics

Completed checks log endpoint/check IDs, success, duration, HTTP status when
available, and a normalized error category. Incident logs add the incident ID and
transition. URLs, credentials, and response bodies are excluded.

Telemetry metrics include:

| Metric | Purpose |
| --- | --- |
| `guru_signal.check.stop.count` | Accepted completions by success/error category |
| `guru_signal.check.stop.duration_ms` | Check duration summary |
| `guru_signal.incident.transition.count` | Incident openings and resolutions |
| `guru_signal.retention.stop.deleted_count` | Pruned result count |
| `guru_signal.retention.stop.duration_ms` | Cleanup duration summary |

IDs are excluded from metric labels. Ignored or discarded attempts do not count
as accepted completions. Development LiveDashboard displays metrics; production
has no configured exporter, durable metric store, or alert delivery.

## History retention

Automatic cleanup is disabled by default. Enable it explicitly at startup:

```bash
RETENTION_ENABLED=true CHECK_RETENTION_DAYS=30 python3 bin/mix-local phx.server
```

The retention window defaults to 30 days and accepts 1–3650. A supervised worker
waits one minute, then runs one batch per minute after the previous batch finishes.
Each transaction locks at most 50 endpoints and deletes at most 1,000 old terminal
check runs. It skips busy endpoints and rotates a cursor across the backlog.

Eligibility uses completion time strictly before the cutoff. Cleanup preserves
pending attempts, the current attempt, and the last accepted result. It rechecks
eligibility under the endpoint lock to avoid deleting a newly accepted result.
Incident records remain; deleted check references become null while incident
timestamps and opening categories survive. Connected owner views refresh after commit.

Changing settings requires a restart. Disabling cleanup cannot restore deleted
history: restoration requires a backup. This policy limits ordinary check history
when cleanup keeps pace, not total database size. Incidents, endpoint count,
backlogs, and protected results remain; deletion does not immediately shrink files.
Performance under a sustained production workload has not been measured.

## Interaction and diagnosis

The UI includes labeled controls, associated validation errors, a skip link,
status announcements, and a public disconnect notice. A full accessibility audit
has not been completed.

For local database connection errors, start PostgreSQL and wait for
`bash bin/dev-db status` to report `running healthy`. Constraint errors in database
logs can be expected during tests that deliberately insert invalid data. Use the
test result and failing assertions to distinguish those from application failures.

For release startup and migration failures, see [deployment](deployment.md).
