# Owner endpoint details

Implemented. The owner ran formatting, compilation with warnings treated as
errors, the full test suite (90 passed), and the asset build successfully, and
verified live detail-page updates across browser tabs. An isolated template
rendering check also covers results, resolved incidents, escaped endpoint names,
and empty states. Mix and PostgreSQL tests ran on the host because the coding
sandbox cannot run them.

## Behavior

Click an endpoint name on `/admin` to open `/admin/endpoints/:id`. This route uses
the existing owner HTTP pipeline and LiveView session authorization. It shows:

- Current configuration and status, including paused and recovering states.
- The latest completed check for the current configuration.
- Up to 50 completed results for this endpoint, newest sequence first.
- Up to 20 incidents for this endpoint, newest opening first, with opening category
  and confirmation timestamps in UTC.

Old configuration results remain visible in history, labeled with their version
and original expected status. They do not establish the current status after an
edit. Pending and discarded attempts are excluded from completed-result history.
This first version has bounded history without pagination.

Both owner views share status/category presentation functions. PubSub completion
and configuration messages refresh the detail view when its endpoint changes.
Deleting that endpoint in another tab returns the detail view to the dashboard.
Missing or malformed identifiers also return to the dashboard with a message.
Editing and manual checking remain available on the dashboard.

No migration or additional dependency is required. These queries expose owner-only
diagnostics; a future public page must select an appropriately restricted view.

## Verification

Stop the running server, then run:

```bash
python3 bin/mix-local format --check-formatted
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local assets.build
python3 bin/mix-local phx.server
```

Database tests cover history filtering, ordering, and limits. LiveView tests cover
protected access, empty states, endpoint-specific results and incidents, live
recovery, configuration changes, missing identifiers, and deletion.

In the browser, click an endpoint name on the dashboard. Keep its detail page open
in another tab while checking or editing the same endpoint on the dashboard. Check
that new results and status changes appear without refreshing. Previous results
should remain in history after an edit. Deleting the endpoint should return the
detail tab to the dashboard. In a signed-out browser, opening its detail URL should
redirect to login.
