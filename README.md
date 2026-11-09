<img src="artwork/guru-signal/guru-signal-banner.png" alt="Guru Signal — Less meditation. More remediation." width="100%">

# GuruSignal

Real-time endpoint monitoring and incident tracking, built with Phoenix LiveView.

**Status: endpoint management, secure HTTP checks, scheduling, result history, and incident tracking implemented.**
The owner verified authentication and endpoint controls in the browser, and
reported passing host checks after the latest fixes. Real checks recorded the
expected success, status mismatch, redirect, and timeout outcomes. Final browser
verification of blocked destinations remains pending. The owner verified live
detail-page updates across browser tabs.
Dependency compilation emits warnings documented in the setup and owner-access
guides. The owner reports successful local verification of incident tracking.
The public status page is implemented; 101 tests pass and the owner verified it
in the browser. Deployment remains pending.
The owner endpoint detail page is implemented; host checks passed with 90 tests.
There is no live demo.

See [the endpoint-management guide](docs/endpoint-management.md) for behavior,
validation rules, and verification commands.
See [HTTP checking](docs/http-checking.md) for the SSRF policy, scheduler limits,
and the new milestone's verification steps.
See [incident transitions](docs/incidents.md) for the three-failure/two-success
rules, concurrency guarantees, and the current milestone's verification steps.
See [endpoint details](docs/endpoint-details.md) for scoped history, live updates,
and verification instructions.
See [public status](docs/public-status.md) for the disclosure boundary, freshness
rules, and verification instructions. Endpoint names are public service labels.
See the [security and concurrency review](docs/security-review.md) for findings,
regression coverage, and remaining deployment limits.
See [health checks and CI](docs/health-and-ci.md) for probe behavior, workflow
configuration, and verification status.
See [accessibility and operational visibility](docs/accessibility-and-observability.md)
for the verified interaction improvements, monitoring metrics, and further accessibility checks.
See [check-history retention](docs/retention.md) for the opt-in cleanup policy,
preserved data, and verification status.

GuruSignal is a single-owner learning and portfolio project. The intended MVP
manages HTTP endpoints, checks them periodically, opens an incident after three
consecutive failures, and resolves it after two consecutive successes. A protected
LiveView dashboard and a public status page expose different levels of detail.

See [the initial architecture](docs/architecture.md) and
[environment findings and setup](docs/setup.md).
See [single-owner administration](docs/owner-access.md) for credential setup,
session behavior, and known limitations.

## Roadmap

- [x] Inspect the available environment and consult official framework documentation.
- [x] Record the proposed architecture, security controls, and local blockers.
- [x] Prepare a PostgreSQL 17 Podman helper; owner verified `running healthy` on the host.
- [x] Generate Phoenix in this directory.
- [x] Resolve dependencies and verify database setup, builds, and generated tests.
- [x] Add and verify single-owner authentication and protected administration.
- [x] Add endpoint management and verify the owner workflow in the browser.
- [x] Implement secure HTTP checks and persisted results; owner reports host tests pass.
- [x] Implement and test incident transitions and duplicate/stale result handling; owner verified locally.
- [x] Add the live owner dashboard with endpoint status, recent checks, and active incidents.
- [x] Add endpoint detail pages; 90 tests pass and the owner verified updates across tabs.
- [x] Add the public status page with restricted data and stale-result handling; 101 tests pass and the owner verified the browser workflow.
- [x] Verify security/concurrency review fixes and additional race tests; 104 tests pass on the host.
- [x] Add accessibility improvements and operational metric/log updates; owner confirmed local verification.
- [x] Add health endpoints; 110 tests pass and the owner verified both HTTP probes.
- [x] Run the GitHub Actions workflow; the owner reports success with three upstream dependency deprecation warnings.
- [x] Add opt-in batched check-history retention and verify its concurrency tests; 127 tests pass on the host.
- [ ] Add release configuration and deployment/recovery documentation.
- [ ] Add verified screenshots and local setup/test instructions.
- [ ] Deploy to Fly.io after explicit approval of resources and cost; verify production.

Notifications, content assertions, latency incidents, regional quorum, teams, and
billing are outside the MVP.

## Agent-assisted development

Codex has assisted with environment inspection, research, and the initial design.
The owner ran Phoenix scaffolding on the host; Codex reviewed and adapted its
local configuration. Implementation and review will continue with agent assistance.
The project owner remains responsible for requirements, design decisions,
validation, and the final result. This section will be updated to reflect work
actually completed.

## License

A license has not yet been selected. The owner must approve the choice before a
license is added.
