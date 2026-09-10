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
- Associate cwd with Git root, repository name, branch, worktree path, sanitized
  origin remote, and nearest package/app directory. Remote credentials must
  never enter the service record or UI.
- Recognize host-published Docker ports without treating the Docker daemon as the app process.

### 5.2 Inventory

The default inventory is a focused `Development apps` view containing directly
openable Web pages that also have project or developer-tool evidence. Services
are grouped by Git project/worktree. Within a project, the nearest application
manifest creates an application subgroup, and directly openable HTTP/HTTPS pages
are app rows beneath it. HTTP-speaking APIs, WebSocket bridges, diagnostic
servers, and endpoints whose root returns an error remain visible as supporting
services of that project. Background services are represented by a compact
relationship icon beside the project title instead of a repeated text row. A
single service shows no count; two or more add a numeric count. Activating the
icon expands the individual services directly beneath the project. The control
uses a quiet capsule at rest so it reads as interactive without competing with
health or runtime state. They retain
evidence and neutral network-reachability context, but do
not offer `Open` or stable `.localhost` actions. LAN reachability becomes a
warning only when a policy or state change requires user review. A project's
primary Web links are always visible and
directly openable; project disclosure must never gate the primary action.
Single-page projects flatten the project/application/service hierarchy into one
row and omit the redundant `1 app` heading. The current Git branch and compact
repository identity remain visible because they distinguish checkouts and
worktrees. When a Web remote is available, the project title opens that
repository at the current branch; the blue local address continues to open the
running page. Multi-page projects retain a static group heading while keeping
every primary link visible. Different worktrees of the same repository remain
separate project groups.

Global `Other Web endpoints` and `Other listeners` disclosures align their text
with primary project titles. Their chevrons occupy the left gutter rather than
creating an additional hierarchy indent; expanded endpoint rows may remain
indented beneath the group label.

Inventory and detail views suppress the native layout-affecting scroller and
show a compact transient position indicator as a pure overlay. It appears only
during a real scroll-position change, forcibly fades after scrolling stops, and
never reserves a right-side gutter or shifts existing rows when a disclosure
makes the view scrollable. Layout-only bounds changes must not reveal the
indicator. This behavior must remain independent of the user's system scrollbar
preference. The inventory document keeps a fixed content width. Expanding a
global secondary section swaps its content without animated geometry; only the
disclosure affordance may animate. Expanded secondary rows keep their leading
hierarchy indent but add no compensating trailing inset; their right-side
metadata uses the same content boundary as the rest of the inventory.

The menu and service-detail surfaces use a compact 382 pt width. Project rows
reserve a stable trailing rail for process age and overflow actions, while the
main repository context may truncate on one line. Global secondary counts share
that tighter trailing boundary. The narrower layout must not reduce the existing
control hit areas or add low-value metadata simply to fill horizontal space.

The primary address itself is the `Open` action. Copy and display-name editing
live in a low-emphasis overflow menu. A subtle pencil beside the address edits
the stable `.localhost` alias inline; the fixed suffix remains visible, Enter
saves, and Escape cancels. The expanded action-card pattern is not used for
normal Web pages.

A collapsed `Other Web endpoints` view contains valid HTTP/HTTPS endpoints with
no developer-project evidence, such as application-internal control APIs. A
second collapsed `Other listeners` view exposes non-Web and unknown TCP
listeners. Users may switch to `All listeners`, but the product must never
claim that a listener is a development app merely because it speaks HTTP or
uses a port common in development.

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
- Open the default HTTP route as `http://<alias>.localhost` without a visible
  port after the user approves the bundled, auditable macOS helper once in
  System Settings. On later launches, detect the helper automatically and use
  port-free routes without further setup. If the helper is unavailable or port
  80 is occupied, fall back visibly to `http://<alias>.localhost:17890` rather
  than silently breaking the address.
- Route by HTTP Host/SNI to an existing HTTP or HTTPS loopback upstream.
- Support normal requests, WebSocket/HMR, server-sent events, streaming responses, redirects, and large request bodies.
- Allow a per-route upstream Host-header mode: preserve public host or rewrite to upstream host.
- Update routes without restarting unrelated upstream applications.
- Detect alias collisions and never silently replace a live route.
- Persist route intent separately from current process state.
- Show a diagnostic response when a named upstream is absent instead of an unexplained generic 502.
- Bind only to IPv4/IPv6 loopback by default.

### 5.5 Distribution and packaging

- Deliver a self-contained macOS `.app` that works after download and drag-copy
  to Applications, without terminal setup.
- Require no separately installed Python, Node.js, npm, Homebrew, Docker, proxy,
  browser extension, or developer tool.
- Keep the HTTP MVP unprivileged and require no `sudo`, CA trust, hosts edit, or
  resolver configuration.
- Treat the current Python and Node prototypes as executable specifications, not
  production runtime choices.
- Validate first launch, upgrade/state migration, and clean uninstall on a clean
  supported macOS account. Detailed constraints are recorded in
  [`packaging-requirements.md`](packaging-requirements.md).

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
| Packaging model | One self-contained macOS app with no external runtime prerequisites | Determines component languages, bundling, signing, updates, and clean-machine tests |
| HTTPS authority | Prototype unprivileged HTTP first; add trusted local CA only after review | CA trust and ports 80/443 are system-level changes |
| Distribution intent | Local-first open-source core; monetization deferred | Affects dependencies, license, update channel, and code signing |
| Data boundary | Store metadata locally; never store response bodies | Defines privacy and security posture |

The product owner confirmed the self-contained, open-box-ready packaging model
on 2026-09-04. It is now a hard constraint for architecture issue #7. HTTPS
authority remains a later privileged acceptance test, not an initial packaging
requirement.

## 12. Open questions to validate, not debate in advance

- How often do real users need to distinguish multiple worktrees of the same repository?
- Should project cards be ordered primarily by recent activity, process age, or
  a user-controlled pinned order?
- Is automatic alias suggestion trusted, or should every alias be explicitly claimed?
- Which frameworks reject the proxy Host header and what default produces the fewest failures?
- Can project identity be recovered reliably when the server was started through an AI agent, package runner, shell wrapper, or Docker?
