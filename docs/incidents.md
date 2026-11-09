# Incident transitions

Implemented. The owner reports successful local verification after receiving
the migration, full-suite, build, and browser-check instructions below.
Five new pure policy tests and six existing endpoint validation tests also
passed in the coding sandbox; changed modules compiled without warnings.

## Rules

- The third consecutive accepted failure opens an incident.
- Further failures keep that same incident open.
- The first successful check shows recovery in progress. The second consecutive
  success resolves the incident.
- Every success resets the failure streak; every failure resets recovery progress.
- Counters saturate at three failures or two successes rather than growing forever.
- All normalized failure categories count, including blocked destinations and
  internal check failures. Ignored, discarded, expired, and superseded attempts
  do not advance either streak.

Opening and resolution timestamps are the completion times of the checks that
confirmed each transition. Incidents are not backdated to the first failure.
The opening failure category is retained; later diagnostic changes remain in
check history. The migration starts counters at zero and does not replay prior
results into retrospective incidents. An existing failed result may show
“Awaiting confirmation” until new checks establish its streak.

Every configuration save, including pausing or re-enabling, resets both streaks.
An existing incident remains open across those changes; pausing is not recovery.
Fresh successful checks after re-enabling can resolve it. Deleting the endpoint
removes its check and incident history.

## Consistency and data

`IncidentPolicy` calculates counter changes and the required action without I/O.
`Incidents` applies them inside `Checks.complete/3`, while that transaction holds
the endpoint's row lock. The accepted check, counters, and incident commit or
roll back together. The public completion return shape is unchanged.

The existing claim identity, sequence, lease, enabled-state, and configuration
version checks run first. Replaying a completed check cannot advance a streak,
open another incident, or resolve one early. SQL constraints limit counter values
and permit at most one open incident per endpoint. A concurrency test uses two
independent PostgreSQL connections to complete the third failure simultaneously.

Incidents store endpoint identity, opening/resolution times, a safe opening
category, and links to the triggering checks. Those links can become null when
[retention](retention.md) removes check rows; the incident timestamps/category survive.
Resolution must not precede opening. Timestamps depend on the host's UTC clock.

The existing committed-check PubSub message refreshes active incidents, recovery
progress, and the twenty most recent incidents in the owner dashboard. An
incident remains visible during its first successful recovery check, even though
that individual check is recorded as successful.

After commit, each actual transition emits
`[:guru_signal, :incident, :transition]` with `%{count: 1}` and safe metadata:
transition (`:opened` or `:resolved`), endpoint ID, incident ID, triggering check
ID, and opening category. Logs use warning for opening and info for resolution.
Do not turn IDs into unbounded metric labels. Repeated or discarded results emit
no incident transition event.
These post-commit signals are best effort; a process failure after commit can
lose a signal, while the database remains authoritative.

## Host verification

Stop the running server, then run:

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local ecto.migrate
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local assets.build
MONITORING_ENABLED=false python3 bin/mix-local phx.server
```

The test suite covers opening, ongoing failure, resolution, a later independent
incident, mixed streaks, repeat completion/events, expired attempts, configuration
changes, pause/re-enable behavior, rollback, database constraints, concurrent
completion, endpoint deletion, and LiveView updates.

For a controlled browser smoke test, keep automatic dispatch disabled as above:

1. At `/admin`, create an enabled endpoint with URL
   `https://httpbin.org/status/503` and expected status `200`.
2. Use **Check now** three times, waiting for each result before requesting the
   next. The first two failures have no incident; the third opens one.
3. Edit that same endpoint's URL to `https://httpbin.org/status/200`. The incident
   should remain open.
4. Check once: the endpoint shows **Recovering (1/2 successes)** and the incident
   stays active. Check again: it becomes healthy and the incident appears resolved
   in history, without refreshing the page.

This manual smoke test depends on the public service being available. Automated
tests use simulated outcomes and require no public Internet. Restart without
`MONITORING_ENABLED=false` afterward to resume automatic development monitoring.

The migration adds one table and two endpoint counters. Rolling it back deletes
incident history and counters; it does not delete existing endpoint/check rows.
Endpoint detail timelines are implemented with passing host tests and verified
updates across tabs; see
[endpoint details](endpoint-details.md). [Public status](public-status.md) is
implemented with 101 passing host tests and an owner-verified browser workflow.
Retention is implemented with 127 passing host tests. Deployment remains later work.
