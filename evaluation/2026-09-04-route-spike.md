# Unprivileged localhost route spike

Date: 2026-09-04  
Status: Compatibility and 15-minute HMR endurance acceptance passing

## Boundary

The prototype listens only on `127.0.0.1:17890` and routes
`http://<alias>.localhost:17890` to existing loopback services. It does not use
ports 80/443, install a certificate authority, edit hosts/resolver files, or
create a launch service.

## Passing evidence

The automated route check currently passes all twenty assertions:

- static HTML routing;
- unknown-alias 404 diagnostic;
- missing-upstream 502 diagnostic naming the exact loopback target;
- upstream Host rewrite plus `X-Forwarded-Host`;
- public Host preservation mode;
- HTTPS upstream routing with explicit verification policy;
- rejection of an untrusted self-signed upstream under the default verification policy;
- relative redirect pass-through;
- external redirect pass-through without following it;
- `Set-Cookie` pass-through;
- server-sent event body preservation;
- server-sent event first-chunk delivery without full-response buffering;
- chunked/streamed response preservation;
- streamed-response first-chunk delivery without full-response buffering;
- 1 MiB request upload with byte count and SHA-256 equality;
- Vite 8 HMR WebSocket `101 Switching Protocols`;
- atomic alias addition without proxy restart;
- atomic alias removal without proxy restart;
- an existing long response surviving eight concurrent atomic route updates;
- an observed IPv4 loopback-only listener.

Vite 8 rejects a WebSocket handshake without its generated HMR token both
directly and through the proxy. Using the token delivered by `/@vite/client`
produces `101 Switching Protocols` and the `vite-hmr` subprotocol through both
paths. This separates a current Vite security requirement from proxy failure.

An additional 900-second endurance run kept both the Vite 8 and Next.js 16 HMR
WebSockets open through the proxy. Disposable copies of both applications were
modified at elapsed seconds 1, 300, 600, and 897. At every update, the new
source marker was visible over HTTP and each framework emitted a new HMR
WebSocket message. Both original connections remained open at the end, with no
socket errors recorded.

HTTPS upstreams verify certificates by default. A route must explicitly select
`insecure-local` to reach a self-signed local development server; the policy is
stored per route rather than weakening TLS globally.

## State and collision behavior

Route state is a versioned JSON document written through `fsync` plus atomic
rename. Adding an identical alias is idempotent. Reusing an alias for a
different port or Host mode fails rather than silently retargeting it. The
running proxy loads the latest complete state for each new request, so route
changes do not restart or disconnect unrelated applications.

## Current implementation choice

The spike uses Node's built-in HTTP, HTTPS, and TCP modules so request/response streams
and WebSocket bytes can be observed directly without introducing another proxy
dependency. This is not yet a recommendation to ship a custom proxy. The
passing results establish the minimum compatibility contract. ADR-0001 selects
a bundled Go standard-library proxy for the first production port, with Caddy
kept behind a route-engine boundary as the fallback if that port cannot pass the
same suite.

## Architecture follow-through

The accepted spike deliberately binds only `127.0.0.1`; LAN reachability is
therefore excluded by construction and by the observed listener. A production
implementation may add a separate `::1` listener for IPv6 localhost support,
but must never use an unspecified or LAN interface. This is an implementation
choice rather than an unresolved compatibility requirement for the IPv4 v0.1
prototype.
