# port-tools

`port-tools` is a proposed local development control plane for discovering forgotten web servers, understanding which project owns them, assigning stable `*.localhost` URLs, and stopping them safely.

The project is currently in discovery and technical-spike stage. Product scope and acceptance criteria live in:

- [`docs/PRD-v0.1.md`](docs/PRD-v0.1.md)
- [`docs/technical-spike.md`](docs/technical-spike.md)
- [`docs/ADR-0001-production-architecture.md`](docs/ADR-0001-production-architecture.md)

The first read-only scanner prototype is runnable now:

```bash
bin/port-tools scan
bin/port-tools scan --json
bin/port-tools scan --all-web
bin/port-tools scan --json --all
```

The default view shows only Web endpoints with developer-project evidence. It
groups by Git worktree first, then by the nearest application manifest, with
multiple live ports shown as service rows.
Sibling monorepo apps remain separate subgroups inside the same project, while
multiple ports from one app stay together. Protocol classification
and developer relevance are intentionally separate in the JSON contract; an
application can expose a valid local HTTP endpoint without being a development
website the user wants to manage.

The safe-stop policy can be inspected without terminating anything:

```bash
bin/port-tools stop <service-id> --dry-run
bin/port-tools stop <service-id> --dry-run --json
bin/port-tools stop <service-id> --graceful
```

The dry run revalidates PID identity and ownership, lists same-project
descendants and excluded processes, describes the graceful `SIGTERM` order,
and records which listeners would need to be released. Docker, other-user,
shared-runtime, and unattributed targets are refused. Graceful stop requires the
separate explicit `--graceful` action, revalidates the complete plan immediately
before signalling, sends only `SIGTERM`, and reports success only after every
target listener is actually released. Force stop is not implemented.

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

The current Python and Node programs are technical-spike implementations, not a
distribution choice. The production macOS app must be self-contained and must
not require the user to install Python, Node.js, npm, Homebrew, Docker, or a
separate proxy. See [`docs/packaging-requirements.md`](docs/packaging-requirements.md).

## Native menu bar app

The current macOS build is a real menu bar app with a bundled, self-contained
Go core. Building it requires Go and Xcode Command Line Tools, but running the
resulting app does not:

```bash
GO_BIN=/absolute/path/to/go native/trial/build.sh
open "native/.build/Port Tools.app"
```

It reads the live Go scanner through a private owner-only Unix socket, groups
development Web services by project, searches projects and services, opens or
copies local addresses, explains Web-detection evidence, and persists custom
display names. A service can claim a real stable URL such as
`http://phone-studio.localhost:17890`; the bundled reverse proxy listens only on
IPv4 and IPv6 loopback, persists routes atomically, and provides a diagnostic
page when the upstream is absent. Stop remains a non-destructive preview.

The release bundle contains no Python or Node runtime. Developer-side Python
fixtures remain in the repository as compatibility specifications while the Go
implementation is brought to full scanner, proxy, and safe-stop parity.

No privileged helper, trusted certificate authority, background service, or
force-termination behavior should be introduced until the corresponding
decision gate in the PRD is resolved.
