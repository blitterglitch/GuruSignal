<img src="artwork/guru-signal/guru-signal-banner.png" alt="Guru Signal — Less meditation. More remediation." width="100%">

# GuruSignal

Real-time endpoint monitoring and incident tracking, built with Phoenix LiveView.

**Status: owner authentication and endpoint management implemented.**
The owner verified login, protected administration, logout, and endpoint controls
in the browser. The previous authentication milestone passed all 12 tests; six
new validation tests pass locally. The latest full-suite summary is not recorded.
Dependency compilation emits warnings documented in the setup and owner-access
guides. Automated checks, incident tracking, and deployment remain pending.
There is no live demo.

See [the endpoint-management guide](docs/endpoint-management.md) for behavior,
validation rules, and verification commands.

GuruSignal is a single-owner learning and portfolio project. The intended MVP
manages HTTP endpoints, checks them periodically, opens an incident after three
consecutive failures, and resolves it after two consecutive successes. A protected
LiveView dashboard and a public status page will expose different levels of detail.

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
- [ ] Implement and test secure HTTP checks and persisted results.
- [ ] Implement and test incident transitions and duplicate/stale result handling.
- [ ] Add the LiveView dashboard, details, and public status page.
- [ ] Review concurrency, SSRF, accessibility, logging, and Telemetry.
- [ ] Add health checks, CI, release configuration, and operational documentation.
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
