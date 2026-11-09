# Secure HTTP checks and persisted results

Implemented. Seventeen new database-independent tests passed in the coding
sandbox. The owner reported successful formatting, compilation, focused TLS,
and full-suite reruns after the fixture and logging fixes; the final console
summary was not supplied. Host migration succeeded, and real checks recorded
expected success, status mismatch, redirect, and timeout outcomes in development
logs. The final browser check of blocked destinations and live result updates
remains to be confirmed before committing.

## Running locally

Stop any existing server, keep PostgreSQL running, then run:

```bash
python3 bin/mix-local deps.get
python3 bin/mix-local format --check-formatted
python3 bin/mix-local ecto.migrate
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local assets.build
python3 bin/mix-local phx.server
```

**Enabled endpoints will make real outbound requests when the development server
starts.** Automatic checking defaults to enabled in development, disabled in
tests, and opt-in in production. To pause automatic dispatch while retaining
owner-triggered checks:

```bash
MONITORING_ENABLED=false python3 bin/mix-local phx.server
```

At `/admin`, use **Check now** for an enabled endpoint. Latest status, timing,
and the twenty most recent completed checks update through PubSub. Edits invalidate
the displayed current result until a result for the new configuration arrives.
History retains the expected HTTP status used by each check.

Response time covers DNS, connection setup, TLS, and receipt of the final response
headers. This is a status-only GET check, not full-body download timing. A 3xx
response succeeds only if that code is explicitly expected; it is never followed.
An endpoint's first failing check is shown as failing. The subsequent
[incident milestone](incidents.md) adds three-failure/two-success thresholds;
the owner verified its implementation locally.

## SSRF controls

Every attempt revalidates the stored URL and resolves DNS at request time. The
checker rejects local names, Fly `.internal` names, single-label names, and any
answer set containing a prohibited address. Both IPv4 and IPv6 are resolved;
errors other than absence of an address family fail closed. Answer sets are
limited to 32 addresses.

IPv4 private, link-local, loopback, shared, multicast, reserved, documentation,
and other IANA special-purpose ranges are blocked. The Azure platform virtual
address is also blocked. IPv6 permits only `2000::/3`, excluding special-purpose,
documentation, and transition ranges inside it. Other IPv6 space, including
mapped IPv4, NAT64, ULA/Fly private addresses, link-local, and multicast, is
rejected. The policy deliberately blocks some globally reachable special-use
services. Review these static ranges as IANA assignments change.

Mint connects to one validated IP tuple, preserving the original hostname for
Host, SNI, and TLS certificate verification. The client has no proxy, redirect,
address fallback, automatic retry, connection pool, or response decompression.
IPv4 is preferred when both families are available. An unreachable selected
address is a failed check even if another address might work.

The endpoint timeout bounds DNS and HTTP together through a supervised task.
Socket operations also use the remaining deadline, and the task is terminated
if the deadline expires. Connection ownership closes sockets if the task dies;
normal client paths explicitly close the connection.

The HTTP/1 parser limits response lines and header sections to 16 KiB. The
accumulator also caps combined headers at 16 KiB and body chunks already returned
alongside headers at 64 KiB. It retains only counters, never bodies, and closes
after final headers. Socket buffers are configured to 8 KiB. These controls bound
application processing; they are not a promise that no additional bytes enter
kernel or TLS buffers before close. Body content is never persisted.

Limitations: unusual routing/NAT, compromised infrastructure, address-policy bugs,
and future allocations remain outside these checks' guarantees. Killing a caller
also does not guarantee cancellation of work already handed to the OS DNS
service. Network egress controls would add another layer. No complete SSRF
protection or multi-node correctness is claimed.

## Scheduling, claims, and completion

One supervised scheduler polls due endpoints once per second. At most four
supervised workers run, with a separate supervisor for their bounded HTTP tasks.
There is no durable job queue or replay of missed intervals: the next due time
advances from the actual claim time. Production must have one continuously
running app machine; autosleep and multiple independent schedulers have not
been validated.

Claiming locks an endpoint row in a short PostgreSQL transaction, assigns a
unique check ID and increasing sequence, snapshots the configuration version
and expected status, and advances its next due time. A lease lasts the request
timeout plus two seconds for completion overhead. A partial unique index allows
only one pending claim per endpoint. A second claim is refused while the lease
is active. A later claim discards an expired pending attempt before starting.

Network I/O runs after the claim transaction commits. Completion locks the same
endpoint and applies a pending result only if its lease, sequence, configuration
version, and enabled state are current. Repeated completion is a no-op. Stale
or expired attempts are marked discarded and do not change current status.
Endpoint deletion cascades claims/history; a subsequent completion returns
not-found. Worker failure may leave a pending claim until a later attempt
supersedes its lease; it does not manufacture a successful result.

Background state updates do not increment the owner's `lock_version`, so normal
checks do not make an open configuration editor stale. Owner edits do increment
it and make an in-flight result ineligible. Configuration writes suppress SQL
parameter logging and redact URL fields; Phoenix also filters URL parameters.
LiveView's automatic lifecycle logging is disabled because its default mount
logger prints unfiltered sessions. Owner tokens stay out of LiveView assigns;
authorization hooks retain them in their closures. Routine scheduler polling
does not emit SQL debug logs. Development check logs include safe identifiers
and categories.

Accepted completions publish a PubSub event, structured safe log metadata, and
`[:guru_signal, :check, :stop]` Telemetry with `duration_ms`, success, endpoint ID,
and normalized category. These occur after commit and only once per accepted
result. Do not use endpoint IDs as unbounded metric labels.

Safe failure categories are connection/DNS, TLS, timeout, unexpected status,
blocked destination, response limit, invalid protocol, and internal check failure.
Raw exceptions, response bodies, and resolved addresses are not stored in results.

## Verification and remaining work

Tests use injected resolvers/clients and local TCP/TLS fixtures; no tests call
public Internet services. TLS fixture certificates and keys are generated under
a temporary directory with the host's `openssl` executable and removed afterward.
There is no production setting to permit private destinations. The low-level
client's local-socket tests exercise it directly; the production checker always
passes through destination authorization.

PostgreSQL tests cover duplicate completion, stale configuration, disabled
endpoints, lease expiry, supersession, cascades, result constraints, and claims
from two independent connections. The unboxed concurrency fixture uses only the
test database and removes its committed row afterward. LiveView tests cover
completion broadcasts and safe result display.

History currently has no automatic retention cleanup. Add and verify batched
retention before production deployment. Incident transitions are implemented;
the owner reports successful local verification. Endpoint detail timelines are
implemented with passing host tests and verified updates across tabs; see
[endpoint details](endpoint-details.md).
Public status projection, deployment, and CI remain later milestones.

References consulted on 2026-11-09:

- [Mint connection and passive receive options](https://mint.hexdocs.pm/Mint.HTTP.html)
- [IANA IPv4 special-purpose registry](https://www.iana.org/assignments/iana-ipv4-special-registry)
- [IANA IPv6 special-purpose registry](https://www.iana.org/assignments/iana-ipv6-special-registry)
