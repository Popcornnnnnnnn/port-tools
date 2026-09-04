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
GET    /v1/routes
PUT    /v1/routes/{alias}
DELETE /v1/routes/{alias}
```

`request` is a small client mode used by the current SwiftUI shell to reach that
socket without adding a second networking implementation. It is not a shell
script and does not make policy decisions.

The route proxy binds to `127.0.0.1` and `::1` only. The initial unprivileged
public form is `http://<alias>.localhost:17890`; it does not edit `/etc/hosts`,
install a certificate, request `sudo`, or expose a public listener.
