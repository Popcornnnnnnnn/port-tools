# Competitive evaluation

This directory contains controlled local fixtures used to evaluate competitor behavior and establish an evidence baseline for `port-tools`.

Current evidence report: [`2026-09-04-competitor-evaluation.md`](./2026-09-04-competitor-evaluation.md)

Fixtures must:

- bind to loopback by default;
- return deterministic content;
- log only protocol metadata required by the test;
- avoid serving arbitrary local directories or files;
- support explicit shutdown and listener-release verification.

## Managed baseline

The managed baseline contains static HTTP, raw TCP echo, self-signed HTTPS,
Vite/HMR, a shell-wrapper child, two worktrees of one repository, and a real
Docker-published HTTP port. Start, verify, and stop it with:

```bash
python3 evaluation/fixtures/manage.py start all
python3 evaluation/fixtures/verify_scan.py
python3 evaluation/fixtures/verify_identity.py
python3 evaluation/fixtures/manage.py clean
```

Runtime PIDs, logs, and the one-day test certificate stay under the ignored
`evaluation/fixtures/.runtime/` directory. The expected classifications are in
`evaluation/fixtures/manifest.json`. `clean` removes the exact disposable
runtime directory and Docker container. It deliberately preserves the shared
Docker image cache because that image may be used by unrelated projects.

## Basic HTTP fixture

```bash
python3 evaluation/fixtures/http_fixture.py --port 51739
```

The fixture returns a fixed HTML page and writes one JSON record per request containing the method, path, Host, User-Agent, and common reverse-proxy forwarding headers.

## Vite fixture

```bash
cd evaluation/fixtures/vite
npm install
portless vite-fixture npm run dev
```

This exercises Portless-assigned ports, HTTPS routing, the Vite client, and HMR WebSocket behavior.

## Caddy loopback fixture

```bash
caddy validate --config evaluation/caddy/Caddyfile --adapter caddyfile
caddy run --config evaluation/caddy/Caddyfile --adapter caddyfile
```

The explicit `bind` directive is intentional. `caddy reverse-proxy --from ...`
was observed listening on all interfaces, while this fixture listens only on
IPv4 and IPv6 loopback.
