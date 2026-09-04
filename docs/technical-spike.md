# port-tools technical spike

Status: Proposed  
Purpose: retire technical risk before UI or production architecture work

## 1. What the spike must prove

The first prototype is intentionally a CLI and local daemon, not a menu-bar UI. It must prove:

1. A listener can be classified as web/non-web with useful evidence and acceptably low false positives.
2. A listener can be associated with the correct process, cwd, Git root, branch, package, and worktree.
3. An existing arbitrary port can be routed through a stable `*.localhost` host while HMR/WebSocket/SSE continue working.
4. A stop action can target the intended owned process tree and prove that its listener was released.

If these fail, a polished UI would only conceal the core reliability problem.

## 2. Competitive hands-on evaluation

Evaluation is necessary, but it should answer concrete questions rather than become a broad feature tour.

### Products

- Port Menu: benchmark discovery speed, grouping, project identity, and stop confirmation.
- PortPeek: benchmark web classification and naming evidence.
- Portless: benchmark alias lifecycle, worktree behavior, Host-header compatibility, HMR, route failure, and cleanup.
- Caddy: benchmark dynamic route reload and local HTTPS as a possible embedded/sidecar engine.

### Safe evaluation stages

Stage 1 requires no owner intervention:

- inspect source, tests, issues, release history, licenses, and architecture;
- run CLI components from temporary directories;
- use high unprivileged ports and loopback-only bindings;
- run disposable fixture servers;
- do not modify the workspace with competitor code.

Stage 2 requires owner confirmation because it changes the Mac:

- install or open signed native menu-bar competitors;
- copy applications into `/Applications`;
- install background launch services;
- bind privileged ports 80/443;
- add a local root CA to Keychain trust;
- modify `/etc/hosts` or DNS resolver configuration.

### Evaluation scorecard

For each product record:

- setup steps and required privileges;
- time until the first useful service appears;
- discovery completeness and false positives;
- process/project/worktree accuracy;
- behavior for Docker and IPv6;
- alias creation/removal behavior;
- Vite/Next.js HMR, WebSocket, SSE, redirects, and cookies;
- stale/missing upstream experience;
- graceful and force-stop safety;
- CPU/memory while idle;
- uninstall residue;
- reusable ideas and mistakes to avoid.

## 3. Fixture matrix

Use disposable local fixtures with deterministic expected results:

| Fixture | Expected classification | Risk exercised |
|---|---|---|
| Static Python HTTP server | confirmed web | basic HTTP/title probing |
| Vite app | confirmed web | random ports, Host checks, HMR/WebSocket |
| Next.js app | confirmed web | framework wrappers, HMR, redirects |
| FastAPI app | confirmed web/API | JSON/docs/content-type behavior |
| HTTPS fixture with local self-signed cert | suspected or confirmed HTTPS | TLS detection and trust boundary |
| TCP echo server | non-web | false-positive resistance |
| Redis/PostgreSQL if already available | non-web | protocol misclassification |
| Docker-published HTTP fixture | confirmed web + Docker owner | host/container ownership |
| two Git worktrees running the same app | two project identities | stable naming/collision handling |
| orphaned shell wrapper with live child | confirmed web | process-tree ownership and cleanup |

## 4. Prototype deliverables

### 4.1 Scanner CLI

Proposed interface:

```text
port-tools scan
port-tools scan --json
port-tools inspect <service-id>
```

The JSON output is the contract for a later SwiftUI or other UI shell. It should contain raw evidence and derived classification separately so heuristics remain auditable.

### 4.2 Route daemon

Run on an unprivileged loopback port during the spike:

```text
port-tools proxy --listen 127.0.0.1:17890
port-tools alias add todo 5173
port-tools alias list
port-tools alias remove todo
```

The spike URL may be `http://todo.localhost:17890`. This intentionally postpones ports 80/443 and CA trust. The route engine must still prove Host routing, WebSocket, HMR, SSE, upstream disappearance, atomic updates, and loopback-only exposure.

### 4.3 Safe-stop dry run

```text
port-tools stop <service-id> --dry-run
```

Dry-run output must show the owner, root PID, descendant PIDs, signals, exclusions, and expected listener. Actual stop tests use only disposable fixtures until the policy is reviewed.

### 4.4 Evidence report

Produce a machine-readable test matrix plus a short decision record covering:

- scanner approach;
- project-identity strategy;
- build-vs-reuse decision for the proxy;
- proposed daemon language;
- UI-shell recommendation;
- blockers before privileged HTTPS testing.

## 5. Architecture decisions the spike should inform

Do not decide the final stack merely from preference. Compare these paths against fixture evidence:

1. Native SwiftUI menu bar + standalone Rust/Go daemon.
2. Tauri/Rust application with menu-bar surface.
3. Native SwiftUI application wrapping Portless or Caddy as the proxy engine.

Initial bias: keep process discovery, route state, and stop policy in one daemon with a versioned local JSON API; keep the UI replaceable. Reuse a proven proxy engine unless the compatibility matrix demonstrates that a small purpose-built proxy is safer to package and maintain.

## 6. Suggested execution order

1. Build fixtures and expected-result manifest.
2. Run read-only competitive/source evaluation.
3. Implement scanner JSON output.
4. Validate project/worktree identity.
5. Implement or wrap an unprivileged route daemon.
6. Test HTTP, HMR, WebSocket, SSE, redirects, and missing upstream behavior.
7. Implement stop dry-run, then disposable-fixture stop verification.
8. Write an architecture decision record.
9. Only then create three visual menu-bar directions and select one before UI implementation.
10. After explicit approval, test the privileged 80/443 and trusted-CA lifecycle.

## 7. Exit criteria

The technical spike is complete when:

- results for every fixture are reproducible;
- web classification failures are explained rather than hidden;
- project identity works for normal repositories and duplicate worktrees;
- HMR/WebSocket works through a stable alias;
- loopback-only binding is verified;
- stop behavior is proven on disposable fixtures without harming unrelated processes;
- build-vs-reuse and stack recommendations cite measured evidence;
- no privileged system changes were required.
