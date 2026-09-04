# port-tools

`port-tools` is a proposed local development control plane for discovering forgotten web servers, understanding which project owns them, assigning stable `*.localhost` URLs, and stopping them safely.

The project is currently in discovery and technical-spike stage. Product scope and acceptance criteria live in:

- [`docs/PRD-v0.1.md`](docs/PRD-v0.1.md)
- [`docs/technical-spike.md`](docs/technical-spike.md)

The first read-only scanner prototype is runnable now:

```bash
bin/port-tools scan
bin/port-tools scan --json
bin/port-tools scan --all-web
bin/port-tools scan --json --all
```

The default view shows only Web endpoints with developer-project evidence and
groups multiple ports under one Git project/worktree. Protocol classification
and developer relevance are intentionally separate in the JSON contract; an
application can expose a valid local HTTP endpoint without being a development
website the user wants to manage.

The safe-stop policy can be inspected without terminating anything:

```bash
bin/port-tools stop <service-id> --dry-run
bin/port-tools stop <service-id> --dry-run --json
```

The dry run revalidates PID identity and ownership, lists same-project
descendants and excluded processes, describes the graceful `SIGTERM` order,
and records which listeners would need to be released. Docker, other-user,
shared-runtime, and unattributed targets are refused. Omitting `--dry-run` is
also refused; no real stop action is implemented yet.

The unprivileged route spike is also runnable without ports 80/443 or a local
certificate authority:

```bash
bin/port-tools alias add studio 4317
bin/port-tools proxy --listen 127.0.0.1:17890
# open http://studio.localhost:17890
```

For a self-signed local HTTPS upstream, the exception is explicit and scoped to
that alias:

```bash
bin/port-tools alias add secure-studio 4443 \
  --upstream-scheme https --tls-policy insecure-local
```

Alias state is updated atomically and live without restarting the proxy. The
compatibility suite covers streaming, SSE, redirects, cookies, large request
bodies, HTTPS upstreams, route updates during a long response, and Vite/Next.js
HMR. The proxy implementation remains a spike, not a final build-versus-reuse
decision.

No privileged helper, trusted certificate authority, background service, or
real process termination behavior should be introduced until the corresponding
decision gate in the PRD is resolved.
