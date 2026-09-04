# Unprivileged localhost route spike

Date: 2026-09-04  
Status: First compatibility baseline passing; Next.js HMR and endurance pending

## Boundary

The prototype listens only on `127.0.0.1:17890` and routes
`http://<alias>.localhost:17890` to existing loopback services. It does not use
ports 80/443, install a certificate authority, edit hosts/resolver files, or
create a launch service.

## Passing evidence

The automated route check currently passes all fifteen assertions:

- static HTML routing;
- unknown-alias 404 diagnostic;
- missing-upstream 502 diagnostic naming the exact loopback target;
- upstream Host rewrite plus `X-Forwarded-Host`;
- public Host preservation mode;
- relative redirect pass-through;
- external redirect pass-through without following it;
- `Set-Cookie` pass-through;
- server-sent event body preservation;
- chunked/streamed response preservation;
- 1 MiB request upload with byte count and SHA-256 equality;
- Vite 8 HMR WebSocket `101 Switching Protocols`;
- atomic alias addition without proxy restart;
- atomic alias removal without proxy restart;
- an observed IPv4 loopback-only listener.

Vite 8 rejects a WebSocket handshake without its generated HMR token both
directly and through the proxy. Using the token delivered by `/@vite/client`
produces `101 Switching Protocols` and the `vite-hmr` subprotocol through both
paths. This separates a current Vite security requirement from proxy failure.

## State and collision behavior

Route state is a versioned JSON document written through `fsync` plus atomic
rename. Adding an identical alias is idempotent. Reusing an alias for a
different port or Host mode fails rather than silently retargeting it. The
running proxy loads the latest complete state for each new request, so route
changes do not restart or disconnect unrelated applications.

## Current implementation choice

The spike uses Node's built-in HTTP and TCP modules so request/response streams
and WebSocket bytes can be observed directly without introducing another proxy
dependency. This is not yet a recommendation to ship a custom proxy. The
remaining compatibility and endurance results will be compared with the
already measured Portless/Caddy behavior before the architecture decision.

## Remaining acceptance work

- Run Vite and Next.js HMR through the alias for 15 minutes and trigger actual
  source updates, not only the WebSocket handshake.
- Add an HTTPS upstream route and record certificate-verification policy.
- Measure first-chunk timing for SSE and streaming rather than only final body
  equality.
- Exercise concurrent route updates and concurrent long-lived connections.
- Decide whether the production listener should bind separate IPv4 and IPv6
  loopback sockets.
