# Port Tools core

The core is the self-contained background engine bundled inside the native
macOS app. It owns listener discovery, HTTP/HTTPS classification, project and
application identity, persistent local routes, and the loopback reverse proxy.

The native app supervises one `serve` process and communicates through a Unix
socket created with mode `0600`:

```text
GET    /v1/health
GET    /v1/capabilities
GET    /v1/services
GET    /v1/services/{id}
GET    /v1/events
PATCH  /v1/services/{logicalID}/preferences
GET    /v1/routes
PUT    /v1/routes/{alias}
DELETE /v1/routes/{alias}
POST   /v1/services/{id}/stop-plan
POST   /v1/services/{id}/graceful-stop
POST   /v1/services/{id}/force-stop-plan
POST   /v1/services/{id}/force-stop
```

`request` is a small client mode used by the current SwiftUI shell to reach that
socket without adding a second networking implementation. It is not a shell
script and does not make policy decisions.

The route proxy binds to `127.0.0.1` and `::1` only. The initial unprivileged
public form is `http://<alias>.localhost:17890`; it does not edit `/etc/hosts`,
install a certificate, request `sudo`, or expose a public listener.

Safe stop is a two-step operation. The first request returns an identity-bound,
single-use plan token and the exact process/listener scope. The second request
revalidates that scope, sends only `SIGTERM`, and succeeds only after every
planned listener has been released. Docker, shared runtimes, other-user
processes, and services without unambiguous Git ownership are refused. A force
plan is available only when SIGTERM was sent and the exact listener remains.
It uses a new single-use token, expires after 30 seconds, revalidates the full
identity again, and sends SIGKILL from descendants to the root process.

`routes.json` is atomically migrated from schema 1 to schema 2. The separate
`inventory.json` preserves logical-service history, names, pin/ignore, and
display-role overrides. Invalid state is backed up with a `.corrupt-<timestamp>`
suffix rather than silently overwritten.

The `watch --socket <path>` command streams `/v1/events` until interrupted.
