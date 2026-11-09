# Accessibility and operational visibility

Implemented improvements. The owner confirmed the requested local verification
works. Three focused component/metric tests also pass in the coding sandbox;
changed source and database/LiveView test modules compile without warnings.
The earlier host baseline was 110 passing tests, with successful CI reported
before these changes. Detailed assistive-technology and visual checks remain
listed below; this is not a conformance certification.

## Interaction and feedback

- A keyboard-visible **Skip to content** link targets the main landmark on the
  public status page, login, dashboard, and endpoint detail page.
- **Edit** moves focus to the endpoint name input. The existing input remains
  the focus target while LiveView updates its configuration values.
- Visible inputs with errors expose `aria-invalid="true"` and reference their
  error container through `aria-describedby`. Existing help-text references are
  preserved. Valid inputs do not reference nonexistent error messages.
- Failed configuration saves include an alert explaining that fields need
  correction. Typing validation remains inline rather than repeatedly alerting.
- Endpoint state labels are polite, atomic status regions. Public/dashboard
  announcements include the service name; timestamps and history tables are not
  live regions, avoiding announcements on every new timing value.
- Status has text labels in addition to color. Tables retain captions/header
  scopes, inputs retain labels, and actions use native buttons/links.
- Public connection-loss feedback remains a status region. Owner pages retain
  their existing reconnect alerts. No JavaScript means public status needs a reload.

These changes are markup and interaction improvements, not a WCAG conformance
claim. Screen-reader output, visible focus, contrast in both themes, 200% zoom,
small-screen horizontal tables, and reconnect behavior need browser review.

## Monitoring metrics

The existing post-commit events now have metric definitions in
`GuruSignalWeb.Telemetry.metrics/0`:

| Metric | Meaning | Tags |
| --- | --- | --- |
| `guru_signal.check.stop.count` | Accepted completed checks | `success`, `error_category` |
| `guru_signal.check.stop.duration_ms` | Check duration summary in milliseconds | `success` |
| `guru_signal.incident.transition.count` | Committed openings/resolutions | `transition` |

Check duration covers DNS, connection setup, and final response headers. These
metrics describe accepted results, not every attempted request: ignored,
discarded, or never-completed claims do not emit completion metrics. Nil error
category denotes a successful check. Tags use bounded booleans/categories/actions;
endpoint/check/incident IDs, names, URLs, and raw errors are not metric labels.

The development LiveDashboard at `/dev/dashboard` can consume these definitions.
Production has no metrics exporter or durable metric store configured yet.
Counters reset with their reporter's lifetime and are not the authoritative
incident history. Production exporter selection and alerting are later decisions.
Telemetry and PubSub are best effort after commit; the database remains authoritative.

Completed-check logs now include success, duration, and HTTP status alongside IDs
and normalized category. Incident logs include the transition action. The logger
formatter includes those safe fields. URLs and response bodies remain excluded.
Scheduler dispatch failures retain a generic error message; there is no scheduler
heartbeat, lease-expiry metric, or alert policy yet.

## Verification

No migration or dependency change is required. Stop the server and run:

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local assets.build
python3 bin/mix-local phx.server
```

Browser checks:

1. On `/`, `/login`, `/admin`, and an endpoint detail page, press Tab from the
   start of the page. The skip link should appear; Enter should focus main content.
2. Navigate to an endpoint's Edit button using the keyboard and activate it.
   Focus should move to the name input with the selected endpoint's value.
3. Submit a URL such as `ftp://example.com`. Confirm the save alert and field error
   are visible, and correction clears the error relationship. A screen reader
   should associate the URL field with its error description.
4. Trigger state changes from another tab. A screen reader should announce the
   service's state change without moving focus or reading the full check table.
5. Use browser network controls to go offline, then reconnect. Check the public
   connection notice and restored updates. Test both themes and 200% zoom.
6. Run a check while viewing development metrics and logs. Look for completion
   count/duration and log outcome fields. Incident transitions should increment
   their metric when their thresholds are crossed.

Automated tests cover input-error relationships for text/select/textarea/checkbox,
preservation of help descriptions, bounded metric tags/units, public status-region
markup, failed-save feedback, and safe/idempotent completion-event metadata.
They do not replace the browser and assistive-technology checks above.

## References

- [W3C WAI form notifications](https://www.w3.org/WAI/tutorials/forms/notifications/)
- [W3C status-message guidance](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html)
- Installed Telemetry.Metrics source for event inference, counters, summaries,
  and units; existing application events for metadata contracts.
