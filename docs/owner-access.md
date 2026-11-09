# Single-owner administration

Authentication is implemented. The owner ran the test suite on the host: all
12 tests passed, with no warnings reported for GuruSignal modules. The owner
confirmed the final compile and browser checks: signed-out access redirects to
login, the configured password opens administration, and logout blocks access
again. [Endpoint management](endpoint-management.md) has since been implemented
and its browser workflow verified by the owner.

PBKDF2 2.3.1 emits three dependency warnings under Elixir 1.20 about unpinned
variables in bitstring size expressions. No dependency files were modified and
no warnings were suppressed.

## Local setup

Keep the PostgreSQL container running. Fetch the new password-hashing dependency:

```bash
python3 bin/mix-local deps.get
python3 bin/set-owner-password
python3 bin/mix-local format
python3 bin/mix-local compile --warnings-as-errors
python3 bin/mix-local test
python3 bin/mix-local phx.server
```

The password helper prompts twice without echoing input. It uses PBKDF2-HMAC-SHA512
with 600,000 rounds and a random salt through `pbkdf2_elixir`. It stores only the
hash in the ignored `.local-tools/owner_password_hash` file with owner-only file
permissions. Use a unique password of at least 16 characters. The Python helper
passes the plaintext to the hashing subprocess through its environment, never
command arguments; it is not a defense against a compromised local account.

`bin/mix-local` reads this hash on subsequent invocations. Restart an existing
server after changing the password. Do not share or commit the hash. Missing
configuration disables login with HTTP 503; there is no default owner password.
The test suite uses its own cheap password hashes solely for test fixtures.

Visit <http://localhost:4000/login>. After login, `/admin` shows a protected
LiveView placeholder. Sign out, then verify that `/admin` redirects to `/login`.
The public home route still shows the generated welcome page.

## Session behavior and limits

- A successful login renews and clears the cookie session and issues a random
  server-side token. The cookie contains no password or password hash.
- Sessions have an absolute eight-hour lifetime. HTTP access, LiveView mount,
  and LiveView events check the token. Connected views also receive an expiry
  timer. Logout revokes the token and broadcasts a LiveView disconnect.
- Sessions and login counters belong to one supervised process in memory.
  Restarting that process or the application invalidates every session. This
  implementation supports one application node; it is not distributed auth.
- At most sixteen sessions are retained; a new login evicts the oldest session
  when that limit is reached.
- A global limit admits five password attempts per fixed minute, including
  successful attempts. Checks are serialized to bound concurrent hashing work.
  The limit does not rely on spoofable forwarded-IP headers. An attacker can
  temporarily block owner login by consuming the allowance. Limits reset on
  restart and do not provide protection across multiple app nodes.
- Password input is capped at 1024 bytes. Login uses the browser CSRF pipeline;
  login/logout/admin responses disable caching. Password, secret, and token
  parameters are filtered from Phoenix request logs.
- Cookies are HttpOnly and SameSite=Lax, with Secure enabled for production
  builds. Production HTTPS enforcement remains in the Phoenix configuration.

## Production configuration

Supply `OWNER_PASSWORD_HASH` as a deployment secret alongside `SECRET_KEY_BASE`.
The local helper is not a production provisioning tool. Password rotation must
restart the application (or explicitly revoke all sessions) to invalidate old
sessions. Database roles are separate from the owner web login. Provisioning and
deployment remain subject to approval and later operational verification.

References: [PBKDF2 library](https://pbkdf2-elixir.hexdocs.pm/Pbkdf2.html) and
[LiveView security](https://phoenix-live-view.hexdocs.pm/security-model.html).
