# Security

## Threat model

An HTTP monitor accepts destinations that its server will contact. A malicious
URL or DNS answer could otherwise reach local services, cloud metadata, or private
networks: server-side request forgery (SSRF). Compromised owner credentials also
permit configuration changes, so outbound checks remain restricted after login.

## Outbound requests

- Accept only HTTP on port 80 and HTTPS on port 443. Reject embedded credentials,
  fragments, malformed hosts, and ambiguous URL characters.
- Resolve A and AAAA records for every check. Reject the entire destination if
  any answer is prohibited, including mixed public/private answers; cap answers at 32.
- Block loopback, private, link-local, multicast, reserved, and special-use ranges,
  including Fly private IPv6 addresses and metadata destinations. Reject local
  hostnames and unsupported address forms.
- Connect directly to a validated IP while preserving the original HTTP Host,
  TLS SNI, and certificate hostname verification. A later DNS lookup cannot
  substitute a different destination during connection establishment.
- Disable redirects, proxies, retries, and decompression. A redirect is a status
  result, successful only when it matches the configured expectation.
- Enforce a shared DNS/HTTP deadline, 16 KiB header limit, and 64 KiB limit on body
  data delivered by the transport. Close after final headers; do not download or
  persist complete response bodies.

These application controls are not an egress firewall. Routing changes, transport
bugs, and future address allocations remain relevant. Keep the IP policy and its
regression tests maintained; private-network monitoring is intentionally unsupported.

## Owner access

The owner password is stored as a salted PBKDF2 hash with 600,000 rounds. There is
no default password; missing configuration makes login unavailable. Local helpers
keep secrets in ignored files rather than command arguments or source control.

Opaque session tokens live in memory for eight hours, with at most 16 sessions.
Restarting invalidates them. Login attempts are limited globally to five per
minute. This simple single-owner limiter can also temporarily lock out the owner.

HTTP routes, LiveView mounts, events, and expiry are checked. Logout revokes the
session and disconnects its LiveView. Forms use CSRF protection; session cookies
are signed, HttpOnly, SameSite=Lax, and Secure in production. Signed cookies are
not encrypted. Production enforces HTTPS, with health-probe exemptions.

## Public data and diagnostics

Public queries select service labels, derived states, check timestamps, and
incident timelines. They exclude URLs, request settings, raw exceptions, response
bodies, and owner credentials. All endpoint names, including paused endpoints,
are public; there is no per-service publication switch.

Logs use IDs and normalized error categories. Sensitive parameters are filtered,
raw LiveView session logging is disabled, and authenticated responses use
`Cache-Control: no-store`. Production does not expose LiveDashboard.

Public connection/rate limits and a network egress policy are not implemented.
Review proxy-header trust and backup access when deploying beyond this project's
single-node scope. See [testing](testing.md) for regression coverage.
