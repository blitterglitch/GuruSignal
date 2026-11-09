# Check-history retention

Implemented. The owner reported 127 passing host tests after correcting the
cleanup/completion race test to accept an endpoint skipped by `SKIP LOCKED`.
Application compilation with warnings treated as errors also passed on the host.
Changed modules compile in the coding sandbox, where two focused worker/options
tests pass. No cleanup has been run against the development database by the agent.

## Policy and activation

Automatic cleanup is disabled by default. Set `RETENTION_ENABLED=true` when
starting the application to opt in. `CHECK_RETENTION_DAYS` defaults to `30` and
accepts integers from 1 to 3650. Automatic cleanup is always disabled in tests.

When enabled, a supervised worker waits one minute, then processes one batch per
minute after the previous batch finishes. Each batch locks at most 50 eligible
endpoints and deletes at most 1,000 check rows. There is no startup purge or
unbounded catch-up loop. The worker rotates an in-memory endpoint cursor so one
endpoint's backlog cannot permanently exclude later endpoints; it wraps to zero
when no later candidates are found. Restarting resets the cursor.

A completed or discarded attempt is eligible when its **completion time** is
strictly older than the retention cutoff. Cleanup always preserves:

- All pending attempts, including expired pending work awaiting supersession.
- The endpoint's current attempt (`check_sequence`).
- Its last accepted result (`last_check_sequence`), even if old or from an earlier
  configuration. Freshness rules still apply; retaining a row does not imply health.

These exceptions preserve status queries and claim bookkeeping. A quiet endpoint
can therefore retain one or two terminal rows beyond the configured window.
Counters, configuration versions, due times, and incident state are not changed.

Incident records are retained. Existing foreign keys set opening/resolution
check references to null when those result rows are deleted; timestamps and the
opening category survive. An open incident can still recover after its opening
result is pruned. Names remain the endpoint's current public label.

This bounds ordinary result history when cleanup keeps pace, not total database
size: incident history, endpoint count, a backlog, and protected rows remain.
Monitor deletion throughput and storage. PostgreSQL vacuuming can reuse deleted
space; deletion does not promise immediate filesystem shrinkage.

## Consistency and feedback

The transaction takes endpoint locks before touching check/incident rows, matching
claim and completion lock order. `FOR UPDATE SKIP LOCKED` skips endpoints busy
in other transactions. Eligibility is queried again after each endpoint is
locked. Independent cleanup workers can safely skip one another's locked rows;
this does not change the application's single-node deployment scope.

Deleting old result rows and updating their incident references commit or roll
back together. A supporting composite index covers endpoint, completion time, and
result ID. No network I/O occurs in the transaction.

After commit, `{:history_pruned, endpoint_id}` refreshes owner dashboard/detail
history. The public page ignores that message because current status and public
incident fields are preserved. Notifications remain best effort.

Successful batches emit `[:guru_signal, :retention, :stop]` with `deleted_count`
and `duration_ms`, and empty metadata. Metrics sum deletions and summarize batch
duration without endpoint tags. Nonempty batches log those counts/timings; failed
scheduled batches log a generic error and retry on the next interval. The worker
retains its cursor on failure.

## Verification

Stop the server, then run:

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local ecto.migrate
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
```

The migration adds an index only; it deletes no data. Tests delete their own
fixtures in the test database and verify batch limits, cutoff semantics,
protected/current rows, discarded and pending attempts, incident preservation and
recovery, cursor rotation, messages/telemetry, and live owner-history updates.
Independent PostgreSQL connections test locked-endpoint skipping, simultaneous
cleanup, and cleanup racing a check completion.

After verification, an explicit development opt-in would be:

```bash
RETENTION_ENABLED=true CHECK_RETENTION_DAYS=30 python3 bin/mix-local phx.server
```

This command deletes eligible old history automatically. Leave the flag unset to
keep automatic cleanup disabled. Changing the flag or retention days requires a
restart. The internal `Retention.prune/1` operation performs one batch even if
the automatic worker is disabled; it is not exposed through a public/admin route.

Before production, choose and document the window and backup policy. Turning
cleanup off or rolling back the index migration cannot restore deleted results;
restoration requires a suitable backup. The first production run and performance
under realistic history volume remain unverified.

## Reference

[PostgreSQL 17 locking clauses](https://www.postgresql.org/docs/17/sql-select.html#SQL-FOR-UPDATE-SHARE)
describe `SKIP LOCKED` and its intentionally incomplete view of busy rows.
