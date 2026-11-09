# Testing

Start PostgreSQL and wait for `running healthy`, then run:

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local assets.build
```

Formatting checks do not change files; `python3 bin/mix-local format` applies
formatting. The test alias creates and migrates the separate test database before
running ExUnit. Tests require local socket access and OpenSSL for TLS fixtures.

## Coverage

Tests focus on observable behavior and failure boundaries:

- Endpoint validation, database constraints, and stale-form rejection.
- Three-failure opening, two-success recovery, and configuration changes.
- Duplicate/stale completions, simultaneous claims, and retention/completion races.
- URL/IP policy, mixed DNS answers, pinned connections, TLS hostname verification,
  timeouts, and response limits.
- Login, session expiry/revocation, protected LiveViews, and public data disclosure.
- Form prefill, live updates, history cleanup, and production configuration.

HTTP and DNS boundaries are injected; socket tests use local servers. Tests do
not depend on public Internet services. Ecto SQL Sandbox isolates ordinary database
tests; concurrency tests use independent connections and clean up their fixtures.
No coverage percentage is required.

To focus a run or reproduce its test order:

```bash
python3 bin/mix-local test test/guru_signal/monitoring/checks_test.exs
python3 bin/mix-local test --seed 518359
```

The seed controls randomized test order, not execution timing. A passing rerun
alone does not establish that a concurrency failure is fixed.

## Continuous integration

[CI](../.github/workflows/ci.yml) runs on pushes to `main`, pull requests, and manual
requests. It installs the pinned Elixir/OTP versions, starts disposable PostgreSQL,
fetches locked dependencies, checks formatting, compiles the application with
warnings as errors, runs tests, and builds assets. It does not build or deploy the
release image; use the [container smoke test](deployment.md#local-container-smoke-test).

Dependencies compile separately so upstream deprecation warnings remain visible
without weakening the application's warning policy. Some dependencies currently
emit deprecated `xref` configuration warnings on the tested Elixir version.
