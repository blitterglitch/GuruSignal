# Endpoint configuration milestone

Implemented at `/admin`, behind the existing owner login. The owner confirmed
that the endpoint workflow behaves correctly on the host. Six database-independent
changeset tests passed locally; the new domain, migration, LiveView, and test
modules also compiled directly against installed dependencies. The owner has
committed this milestone; its full Mix test output was not captured in the
conversation. See [HTTP checking](http-checking.md) for the subsequent work.

## Behavior

The owner can create, list, edit, enable, pause, and delete endpoints. Inline
validation keeps invalid input in the editor. Deletion requests browser
confirmation. Connected admin views refresh their lists through PubSub when
configuration changes.

| Field | Rules and defaults |
| --- | --- |
| Name | Required, trimmed, at most 100 characters |
| URL | Required, trimmed, at most 2048 characters |
| Expected HTTP status | Final response code, 200–599; default 200 |
| Check interval | 60, 300, or 900 seconds; default 60 |
| Timeout | 1000–10000 milliseconds; default 5000 |
| Enabled | Boolean; default true |

URLs must use HTTP port 80 or HTTPS port 443, with a syntactically valid ASCII
hostname (or IP literal), no embedded credentials, fragments, whitespace, or
backslashes. Punycode hostnames are supported; Unicode hostnames must first be
converted to their ASCII form. Different configurations may share a name or URL.

Configuration validation itself performs **no outbound requests or DNS lookups**.
URL syntax validation is not SSRF protection: private destinations can be stored,
but the subsequent [HTTP checker](http-checking.md) must authorize them at request
time before connecting. That checker and its results UI are now implemented and
awaiting host integration verification. Endpoint URLs are filtered from Phoenix
parameter logs because their query strings may contain sensitive values.

## Domain and concurrency

`GuruSignal.Monitoring` owns CRUD operations. `Monitoring.Endpoint` maps to the
new `endpoints` table and builds changesets. SQL constraints enforce required
fields, supported numeric values, nonblank names, basic URL shape, and positive
configuration versions. Full URL syntax remains an application validation;
request-time destination controls must be independent of stored data validation.

`lock_version` supplies optimistic concurrency: updates and deletes require the
version that was originally read. Even a no-change save checks and advances the
version. A stale editor receives a recoverable message instead of silently
overwriting newer data. Connected list refreshes preserve an editor's snapshot
so that competing changes remain detectable. IDs and versions cannot be assigned
through submitted endpoint attributes. No multi-node scheduler behavior is
implemented or claimed.

## Verify on the host

With the database running:

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local ecto.migrate
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local assets.build
python3 bin/mix-local phx.server
```

The test command creates/migrates its separate test database automatically.
Tests cover validation boundaries, CRUD persistence, database constraints that
bypass changesets, stale update/delete rejection, malformed identities, form
errors, endpoint controls, and connected-list updates. Existing authentication
tests continue to cover the protected route and LiveView mount.

In the browser, log in and create an endpoint such as `https://example.com/health`.
Verify persistence after refreshing, edit its settings, pause and re-enable it,
then delete it. Verify invalid settings are rejected and another open admin tab
updates. To check conflicts, edit in both tabs, save in one, then submit the old
editor in the other; it should ask you to select Edit again.

The migration creates one new table and does not change existing tables. Its
rollback drops endpoint configurations, so run rollback only when those local
records can be discarded. Host migration/build/test results must be recorded
before marking this milestone verified or committing it.
