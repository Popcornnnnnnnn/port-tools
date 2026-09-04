# port-tools PRD v0.1

Status: Draft for problem validation  
Date: 2026-09-04

## 1. Product statement

`port-tools` is a local-first control plane for vibe-coding projects. It automatically discovers local web services, connects each service to its process and project context, gives it a stable human-readable `*.localhost` URL, and lets the user open, retain, or stop it safely.

The product is not a generic network scanner and not a full replacement for Docker Desktop, launchd, or a terminal.

## 2. Target user and job

Primary user: a developer or AI-assisted builder who starts many temporary Vite, Next.js, FastAPI, static, or similar local servers across repositories and Git worktrees.

Job to be done:

> When I return to development after hours or days, show me which local web apps are still alive, what project created each one, whether it is exposed beyond my machine, and give each app a stable address so I can safely resume or clean it up without reconstructing terminal history.

## 3. Problem definition

The product must answer four distinct questions. A listening port alone is insufficient evidence for any of them.

1. Is this TCP listener actually a web service?
2. Which process, command, project, branch, and worktree does it belong to?
3. Is it intentional, unmanaged, or plausibly forgotten?
4. Can it be reached through a stable local name independent of its current port?

## 4. Product principles

- Local-only by default: no account, cloud sync, telemetry, or public tunnel in MVP.
- Evidence over guesses: show why a service was classified and why it is considered possibly stale.
- Never auto-kill: suspected stale services require an explicit user action.
- Graceful before forceful: terminate the owned service or process group safely; do not kill shared runtimes or Docker itself.
- Stable project identity: a route belongs to a project/worktree identity, not merely to a transient PID or port.
- Reversible system changes: privileged helpers, CA trust, hosts entries, and launch agents must have explicit status and clean uninstall paths.

## 5. MVP scope

### 5.1 Discovery

- Enumerate current-user TCP listeners on IPv4 and IPv6.
- Record PID, executable, command line, owner, parent PID, start time, cwd, bind address, and port where available.
- Classify bind scope as loopback-only, LAN/all-interfaces, or unknown.
- Probe likely HTTP and HTTPS endpoints with strict time and response-size limits.
- Classify each listener as confirmed web, suspected web, non-web, or unknown.
- Extract safe metadata such as status code, content type, page title, and server header.
- Associate cwd with Git root, repository name, branch, worktree path, and nearest package/app directory.
- Recognize host-published Docker ports without treating the Docker daemon as the app process.

### 5.2 Inventory

The default inventory is a focused `Web apps` view containing confirmed and
suspected Web services. A separate, collapsed `Other listeners` view exposes
the complete TCP inventory for diagnosis without overwhelming the primary
workflow. Users may switch to `All listeners`, but the product must never claim
that a listener is Web merely because its process or port is common in
development.

Each service record should show:

- stable internal service ID;
- current URL and port;
- web classification and evidence;
- process, command, cwd, and project identity;
- Git branch/worktree;
- first seen, process start time, last seen, and last successful probe;
- bind exposure;
- management source: unmanaged process, port-tools-managed, Docker, launchd, Homebrew, or unknown;
- optional user label and ignored/pinned state.

Filtering requirements:

- do not exclude a listener solely because its port is low, high, uncommon, or
  ephemeral;
- use successful bounded HTTP/HTTPS protocol evidence as the strongest Web
  signal;
- combine response status/headers/content type/title with process command,
  script path, framework, cwd/project, and management source;
- treat known-port mappings as low-confidence hints only;
- keep non-Web and unknown listeners discoverable outside the default view;
- allow the user to pin, ignore, or manually reclassify a service without
  discarding the underlying evidence.

### 5.3 Actions

- Open in browser.
- Copy raw URL or stable local URL.
- Reveal project directory.
- Assign, edit, or remove a stable alias.
- Ignore or pin a service.
- Send graceful termination only to an eligible current-user process.
- Offer force termination only after graceful termination times out and after a second confirmation.
- Confirm that the port is released after termination.

### 5.4 Stable local routes

- Default public name: `<alias>.localhost`.
- Route by HTTP Host/SNI to an existing HTTP or HTTPS loopback upstream.
- Support normal requests, WebSocket/HMR, server-sent events, streaming responses, redirects, and large request bodies.
- Allow a per-route upstream Host-header mode: preserve public host or rewrite to upstream host.
- Update routes without restarting unrelated upstream applications.
- Detect alias collisions and never silently replace a live route.
- Persist route intent separately from current process state.
- Show a diagnostic response when a named upstream is absent instead of an unexplained generic 502.
- Bind only to IPv4/IPv6 loopback by default.

## 6. Staleness model

MVP must use the label `possibly forgotten`, never `unused`, because process age does not prove user intent.

Candidate evidence includes:

- long process age;
- dead or unrelated parent terminal;
- missing project directory;
- repeatedly failed health probes;
- an unmanaged listener that has not been pinned or named;
- an old route whose upstream PID has disappeared.

CPU usage and connection activity may be added later. They are not required for the first scanner because sampling them reliably introduces additional OS-specific behavior.

## 7. Primary flows

### Flow A: rediscover work

1. User opens the menu-bar panel.
2. Services are grouped by project/worktree rather than raw port number.
3. User sees title, branch, URL, age, and exposure at a glance.
4. User opens the app or reveals its project directory.

### Flow B: claim a stable name

1. User chooses an unnamed confirmed web service.
2. Product suggests a slug derived from project/package name.
3. User accepts or edits it.
4. Product validates the alias and proxy compatibility.
5. `https://<alias>.localhost` becomes the primary URL.

### Flow C: clean up a forgotten service

1. Product labels a service as possibly forgotten and exposes its evidence.
2. User selects Stop.
3. Product explains the exact PID/process tree it will affect.
4. Product sends a graceful signal and verifies port release.
5. Force-stop is offered only if needed.

## 8. Success measures

Initial measures are local and opt-in to review; no telemetry is required.

- At least 95% of the agreed Vite, Next.js, FastAPI, and static-server fixtures are correctly classified.
- No database fixture is classified as confirmed web.
- A newly started service appears within 5 seconds under the default refresh setting.
- Project root and worktree are correct for all repository fixtures.
- Stable aliases survive an upstream restart and can be rebound when its port changes.
- Vite and Next.js HMR work through the alias for a 15-minute interactive session.
- Every Stop action identifies the target first and verifies the result afterward.
- Clean uninstall leaves no trusted CA, hosts-file block, privileged helper, or launch item created by the product.

## 9. Explicit non-goals for MVP

- Public internet tunnels or remote sharing.
- Team accounts, cloud sync, authentication, or billing.
- Full application launcher/process supervisor.
- Capturing request bodies or browser traffic.
- Editing project source or package scripts automatically.
- Windows/Linux parity.
- Automatic cleanup based only on a heuristic score.

## 10. Competitive baseline

- Port Menu: native macOS discovery, project/branch context, open and stop actions.
- PortPeek: TCP listener discovery plus HTTP title/server-header probing.
- Portless: stable named localhost URLs, aliases for existing ports, HTTPS, HMR/WebSocket support, worktree-aware naming, route diagnostics, and cleanup commands.
- Caddy: robust reverse-proxy and local-HTTPS building block.

The product opportunity is the combined loop: discover an app that port-tools did not start, establish project identity, claim a stable route, remember that route across port changes, and later stop the exact service safely.

## 11. Decision gates requiring product-owner confirmation

Defaults are proposed so discovery work can continue before these are answered.

| Decision | Proposed default | Why confirmation matters |
|---|---|---|
| Initial platform | macOS 14+, Apple Silicon first | Determines UI shell, process APIs, signing, and test matrix |
| Product surface | Native menu bar + CLI/JSON daemon API | Determines architecture and whether a browser dashboard is needed |
| Management scope | Discover/open/name/stop existing apps; do not launch apps in MVP | Prevents expansion into a process supervisor |
| HTTPS authority | Prototype unprivileged HTTP first; add trusted local CA only after review | CA trust and ports 80/443 are system-level changes |
| Distribution intent | Local-first open-source core; monetization deferred | Affects dependencies, license, update channel, and code signing |
| Data boundary | Store metadata locally; never store response bodies | Defines privacy and security posture |

Only the first three decisions affect the immediate implementation architecture. HTTPS authority affects a later privileged acceptance test, not the initial scanner.

## 12. Open questions to validate, not debate in advance

- How often do real users need to distinguish multiple worktrees of the same repository?
- Do users prefer services grouped by project, by recency, or by status?
- Is automatic alias suggestion trusted, or should every alias be explicitly claimed?
- Which frameworks reject the proxy Host header and what default produces the fewest failures?
- Can project identity be recovered reliably when the server was started through an AI agent, package runner, shell wrapper, or Docker?
