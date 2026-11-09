# GuruSignal

Real-time endpoint monitoring and incident tracking, built with Phoenix LiveView.

**Status: design and environment verification only.** The application has not yet
been scaffolded, tested, or deployed. There is no live demo.

GuruSignal is a single-owner learning and portfolio project. The intended MVP
manages HTTP endpoints, checks them periodically, opens an incident after three
consecutive failures, and resolves it after two consecutive successes. A protected
LiveView dashboard and a public status page will expose different levels of detail.

See [the initial architecture](docs/architecture.md) and
[environment findings and setup](docs/setup.md).

## Roadmap

- [x] Inspect the available environment and consult official framework documentation.
- [x] Record the proposed architecture, security controls, and local blockers.
- [ ] Generate Phoenix in this directory; resolve dependencies and verify compatibility.
- [ ] Add endpoint management and single-owner authentication.
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
The planned workflow also uses Codex for scaffolding, implementation, and review.
The project owner remains responsible for requirements, design decisions,
validation, and the final result. This section will be updated to reflect work
actually completed.

## License

A license has not yet been selected. The owner must approve the choice before a
license is added.
