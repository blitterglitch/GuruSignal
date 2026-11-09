# Security and concurrency review

Reviewed on 2026-11-09. This is a source review and targeted regression work,
not an external security audit or a claim of complete SSRF protection.

## Finding and fix

`Checker` rescued raised exceptions inside its network task, but did not catch
Elixir throws or process exits. An injected client reproduced the gap: both
returned an `internal` outcome to the caller, yet their sensitive payloads were
printed in task crash logs. The task now normalizes throws and exits at the same
boundary before they reach the crash logger. Forced task termination still
works; this does not catch an external untrappable kill.

The regression failed against the previous implementation and passes after the
fix. It checks both safe outcomes and absence of sensitive payloads in logs.
Existing deadline tests still verify that hanging DNS/HTTP tasks are terminated.
No production secrets or public Internet requests were used to reproduce it.

## Boundaries examined

| Boundary | Implementation and evidence |
| --- | --- |
| Outbound destination | URL syntax validation, request-time A/AAAA resolution, rejection of mixed prohibited answers, and a pinned IP connection. Existing tests cover rebinding, local/metadata/Fly-private addresses, aliases, and range edges. |
| HTTP and TLS | Standard ports, fresh HTTP/1 connections, original hostname verification, no redirects/proxies, total deadline, bounded headers/body events, and socket cleanup. Controlled TLS socket tests run on the host. |
| Owner access | HTTP owner pipeline, LiveView mount/event authorization and expiry, revocable server sessions, login throttling, CSRF protection, and Secure production cookies. Existing tests cover protected routes, revocation, expiry, and missing configuration. |
| Public data | Explicit restricted projection; no URLs, request settings, check diagnostics, or owner tokens in public assigns. Service names are deliberately public labels. |
| Logging | Filtered sensitive parameters, suppressed LiveView session logging, normalized check outcomes, safe structured IDs/categories, and the new throw/exit fix. |
| Database writes | Claim/completion transactions serialize on the endpoint row. Network I/O runs outside them. Configuration updates use optimistic locking and force counter resets even from older snapshots. |
| Incident transitions | Check persistence, streaks, and incident changes share one transaction. A partial unique index allows one open incident. Repeat/stale/expired completions cannot advance streaks. |

## Additional race coverage

Two new PostgreSQL tests use independent connections and a start barrier:

- Completing the second recovery success twice concurrently records one result,
  ignores its duplicate, and resolves the incident with that check only once.
- A configuration edit races the third failed completion using an older editor
  snapshot. If completion wins the lock, its incident opens before the edit and
  remains open. If editing wins, the old result is discarded. Both outcomes must
  leave the new configuration with zero streak counters.

These supplement the existing independent-connection claim race and duplicate
incident-opening test. A start barrier permits competing transactions; it does
not exhaust every interleaving or prove multi-node operation.

## Verification status

In the coding sandbox, 33 focused tests passed across URL/address policy,
destination authorization, fake HTTP transport, response bounds, checker error
handling/deadlines, incident rules, and public freshness rules. Changed source
and database-test modules compiled without warnings; `git diff --check` passed.

The owner ran formatting, compilation with warnings treated as errors, and the
full suite successfully: 104 tests passed with seed 207650, including the two
new PostgreSQL races and real TLS socket fixtures. Reproduce the checks with:

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
```

For a browser SSRF check, configure `http://127.0.0.1` as an enabled endpoint and
use **Check now**. Owner history should show **Destination blocked**, with no HTTP
status. Its public service may show a failing check or incident but must not show
the destination or rejection category. Remove the fixture afterward.

## Remaining limits and deployment work

- The address policy is application-level defense. Routing, NAT, future address
  allocations, and transport defects remain outside its guarantees. Maintain the
  policy and consider network egress restrictions; private access has no bypass
  switch.
- Scheduling and owner sessions deliberately support one application node.
  Restarting invalidates owner sessions. No durable notification outbox exists;
  post-commit PubSub/Telemetry can be lost without losing committed data.
- Public visitors currently have no connection/rate limit. Each connected view
  reloads on broadcasts and every 30 seconds. Review capacity and edge limits
  before exposure; the global login limit also permits temporary owner lockout.
- Results have no retention cleanup yet. Service count and active-incident lists
  are not capped. Bound storage growth before production.
- Production enables HTTPS enforcement and Secure cookies, but proxy/header
  trust, database TLS, secrets, release configuration, and health checks need
  validation against the actual deployment topology. Dev diagnostic routes are
  intended for local development.
- Accessibility/browser connection-loss checks, operational Telemetry review,
  dependency advisory checks, and CI remain separate work. Passing these tests
  does not constitute a complete production readiness review.
