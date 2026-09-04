# Scanner fixture matrix

Date: 2026-09-04  
Status: Complete for scanner classification; transport behavior continues in route spike

## Outcome

The reproducible scanner matrix now contains fourteen fixtures. All twelve Web
fixtures were classified as confirmed Web, and both non-Web fixtures were kept
out of the default inventory.

| Fixture | Expected | Observed | Extra evidence |
|---|---|---|---|
| Static HTTP | confirmed HTTP | pass | HTML title |
| Self-signed HTTPS | confirmed HTTPS | pass | TLS handshake plus untrusted certificate |
| Vite | confirmed HTTP | pass | `vite` framework marker |
| Next.js 16 | confirmed HTTP | pass | `next` framework marker and cold-start retry |
| FastAPI | confirmed HTTP | pass | JSON content type and `fastapi` framework marker |
| Shell-wrapper child | confirmed HTTP | pass | project recovered from absolute command path |
| Primary worktree | confirmed HTTP | pass | main branch/worktree identity |
| Feature worktree | confirmed HTTP | pass | separate worktree identity |
| Docker nginx | confirmed HTTP | pass | Docker and Compose project ownership |
| Monorepo app | confirmed HTTP | pass | nearest package/app root and package name |
| Ambiguous command | confirmed HTTP | pass | two project candidates retained without guessing |
| Unlabeled Docker nginx | confirmed HTTP | pass | container identity retained; host project not inherited |
| TCP echo | non-Web TCP | pass | echoed request rejected as an HTTP response |
| Redis 7 | non-Web Redis | pass | RESP `PONG` after Redis-specific evidence |

This is 100% classification on the agreed first matrix and zero confirmed-Web
false positives for the two non-Web protocols.

## Cold Next.js behavior

Next.js listened before its first page compilation completed. Its initial `/`
response took 561-577 ms, beyond the scanner's normal 450 ms read budget;
subsequent requests took 12-20 ms. The scanner now performs one bounded 1.2 s
retry only when command evidence identifies a Web framework such as
`next-server`. It does not increase the timeout for every unknown listener.

The first Next.js run also created `AGENTS.md` and `CLAUDE.md` inside the fixture
and initialized its anonymous-telemetry configuration. Those generated files
were not read or followed. `agentRules: false` and
`NEXT_TELEMETRY_DISABLED=1` now prevent those behaviors for the fixture. The
generated rule files were removed, and the newly created telemetry directory
was moved to Trash so recovery remains possible.

## Redis behavior

Redis 7 intentionally closes connections carrying an HTTP-shaped request, so
absence of an HTTP response is not enough to distinguish it from an unknown
listener. The scanner sends a read-only RESP `PING` only after process or Docker
metadata identifies Redis; it never uses the port number alone. A valid
`+PONG` produces `classification=non-web`, `protocol=redis`, and
`redis-response` evidence.

## Performance and data boundary

With all fourteen fixtures active, a full scan of this Mac completed in 3.8
seconds. HTTP probing uses raw requests, does not follow redirects, reads at
most 64 KiB, and emits only status/header/title/framework evidence rather than
response bodies.

## Cleanup evidence

The managed cleanup stopped all processes and three containers, observed release
of ports 51739 through 51753, removed the generated FastAPI virtual environment,
worktree repositories, certificate, logs, and Next.js build output. The shared
Docker image cache and checked-out Node dependencies are deliberately retained;
they are dependency caches rather than listeners or services and may be shared
with other work.

Direct HMR/WebSocket, SSE, redirects, uploads, streaming, and proxy Host-header
behavior are intentionally measured in the route spike rather than inferred
from scanner classification.
