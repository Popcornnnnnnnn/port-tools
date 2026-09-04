# Competitive evaluation — 2026-09-04

Status: In progress  
Platform: macOS 26.6.2, Apple Silicon (`arm64`)

This report separates runtime observations from source-derived behavior. It is
not a feature-list comparison. Each result answers a product or architecture
question in the `port-tools` spike.

## Installed test subjects

| Product | Tested version | Installation used | Runtime status |
|---|---:|---|---|
| Port Menu | 0.8.10 | `/Applications/Port Menu.app` | Installed, notarized signature accepted, app launched |
| PortPeek | 1.0.0 | Built from source and copied to `/Applications/PortPeek.app` | Installed, ad-hoc signed, app launched |
| Portless | 0.15.6 | Global npm package | Proxy and managed Vite route tested |
| Caddy | 2.11.4 | Homebrew formula | CLI proxy tested, then stopped cleanly |

Source revisions inspected:

- Port Menu: `wieandteduard/port-menu@8acafa9a77b3df0b19bfa59100f8abdd4481717e`
- PortPeek: `pablomanjarres/PortPeek@5123889e1b0f28355bc9c0247ae39719884e91a0`
- Portless: `vercel-labs/portless@1ad573bb95810daf6cd50c1718707015450f3f09`

## Executive result

No tested product closes the whole loop we want:

1. discover an arbitrary existing web service;
2. explain its process/project/worktree identity and exposure;
3. give it a durable local name independent of its current port;
4. later stop the exact owned service with preflight and post-stop proof.

Port Menu has the strongest native project-oriented inventory, PortPeek adds a
real HTTP probe, Portless has the strongest named-route lifecycle, and Caddy is
a capable proxy building block. The product opportunity is their safe,
evidence-oriented integration rather than another raw port list.

## Port Menu

### Runtime evidence

- Release app was copied to `/Applications`, its code signature verified, and
  Gatekeeper reported `source=Notarized Developer ID`.
- The app launched as a menu-bar-only process.
- A user-provided screenshot confirms the live menu-panel inventory. It clearly
  exposes project name, Git branch, port, and process age, and it shows multiple
  concurrent services for the same repository. See the focused
  [UI audit](./2026-09-04-port-menu-ui-audit.md).
- Automated interaction with the menu panel is still pending because the
  available UI automation surface did not expose this `LSUIElement` app.
- The inventory showed a long-running listener as `node :19201`. Direct
  inspection recovered the real identity as launchd job
  `com.boonray.mine-cloud-proxy`, executing
  `Boonray/local/private/tools/mine-cloud-proxy.mjs`. Its cwd is `/`, so Port
  Menu could not find a Git root and fell back to the allow-listed process name
  `node`.
- The listener on `127.0.0.1:19201` speaks HTTP but currently returns 502 with
  `Tunnel target unavailable: connect ECONNREFUSED 127.0.0.1:19211`. Port Menu's
  green listener state does not communicate this degraded upstream state.

### Source evidence

- Discovery runs `lsof -iTCP -sTCP:LISTEN -n -P`, then resolves cwd and Git
  metadata.
- It intentionally excludes ports below 1024 and ports at or above 49152.
  Therefore a valid fixture on port 51739 is invisible by design.
- It does not probe HTTP content. A listener is selected using process/project
  heuristics, then its Open action assumes `http://localhost:<port>`.
- A row-level Kill sends `SIGTERM` immediately. Kill all sends `SIGTERM` to all
  current entries immediately. There is no target preview, graceful timeout,
  force-stage escalation, or explicit port-release verification.

### Product implication

Project context is valuable, but a fixed port range is an unacceptable proxy
for “development web service.” Discovery and web classification must be
separate evidence stages. Destructive actions need a stronger ownership and
verification contract.

The `node :19201` case also proves that cwd alone is not enough for identity.
When cwd is unhelpful, `port-tools` should inspect the executable arguments,
script path, ancestors, and launchd metadata. The desired presentation is
approximately `Boonray · mine-cloud-proxy`, managed by launchd, with `proxy
upstream unavailable` as its health state. Stop must target the launchd job
lifecycle rather than killing a PID that launchd will immediately restart.

## PortPeek

### Runtime evidence

- A fixture on `127.0.0.1:41731` received a GET with user agent
  `PortPeek/1.0.0 CFNetwork/3860.700.1 Darwin/25.6.0`.
- A second fixture on port 51739 received the same probe, demonstrating that
  PortPeek does not share Port Menu's high-port blind spot.
- While Caddy was running, PortPeek also probed Caddy's local admin endpoint on
  port 2019. This demonstrates discovery breadth but also why the product must
  distinguish “HTTP-speaking” from “user-facing web app.”
- On the evaluation Mac, the original popover reported `37 open` but rendered
  no port rows: only the header, filter field, and footer were visible. The
  count is a non-interactive text label, so clicking it correctly did nothing.
  Screenshot: [original empty-list state](./screenshots/02-portpeek-empty-list.png).
- Source inspection found that the populated `ScrollView` only declares
  `.frame(maxHeight: 380)` inside a window-style `MenuBarExtra`. On this system
  its ideal height collapsed to zero. No runtime exception was logged.
- For continued intent-level evaluation, a clearly separate local build named
  `PortPeek Patched.app` was created with an explicit bounded list height. The
  untouched original remains installed; observations from the patched build
  must not be attributed to the released product.
- The patched build then rendered the intended 37-row inventory, confirming the
  layout diagnosis. [Patched-list screenshot](./screenshots/03-portpeek-patched-list.png).
- That inventory exposed unsafe semantic shortcuts in the underlying product:
  a real Vite app on 4317 was tagged `OpenTelemetry`; macOS Control Center's
  AirTunes listener on 5000 was tagged `Flask / Python`; and QEMU's listener on
  5555 was tagged `Prisma Studio`.

### Source evidence

- It scans TCP listeners with `lsof` and issues an ephemeral URLSession GET to
  `http://localhost:<port>` with a two-second timeout.
- It extracts an HTML title and falls back to the Server response header.
- Its label function checks a hard-coded known-port dictionary before process
  evidence. The observed incorrect labels exactly match entries for ports 4317,
  5000, and 5555 in that dictionary.
- The UI asks for a second click with `Kill?`, then the backend runs
  `kill <pid>`, waits 500 ms, and rescans.

### Product implication

An HTTP probe materially improves discovery, but a single GET and title are
classification inputs, not the classification itself. We should cap response
size, use staged protocol detection, retain raw evidence, and suppress known
control/admin endpoints unless explicitly requested.

Known-port data may be displayed only as a low-confidence hint. It must never
override contradictory process, HTTP-title, bind-scope, or project evidence.
For example, `Phone 3D UI Studio` is stronger evidence than the conventional
meaning of port 4317.

The empty-list failure also establishes a UI acceptance requirement: the
scanner count and rendered rows must be cross-checked, including large result
sets and current macOS releases. A popover that claims results but shows none
needs an explicit recoverable error rather than silent empty space.

## Portless

### Runtime evidence

- The first background proxy start could not elevate to privileged port 443,
  so it fell back to HTTPS on port 1355. It bound only `127.0.0.1:1355` and
  `[::1]:1355`.
- `portless doctor` reported the proxy healthy and the generated local CA as
  trusted. HTTPS verification succeeded with `ssl_verify_result=0`.
- An alias routed `https://spike.localhost:1355` to the existing fixture on
  `127.0.0.1:41731` and returned HTTP 200.
- A managed Vite process was assigned port 4945 and routed as
  `https://vite-fixture.localhost:1355`.
- A valid Vite HMR WebSocket handshake returned `101 Switching Protocols`,
  negotiated `vite-hmr`, and delivered `{"type":"connected"}`.
- A route pointed at unused port 41732 produced Portless's branded HTTP 404
  diagnostic page, including the missing hostname and links to active apps.
- Re-registering an alias-owned hostname silently replaced its target. A
  collision with a live managed route was rejected with exit status 1 and the
  owning PID. The original alias was restored and retested successfully.
- One immediate request just after restoring an alias returned 502; the next
  request returned 200. Route update propagation therefore needs an atomicity
  and transient-error test, not only a steady-state test.

### Source evidence

- Normal proxy mode binds only IPv4 and IPv6 loopback; LAN exposure is an
  explicit mode.
- Managed frameworks receive a loopback host plus Portless-assigned port and
  URL environment.
- Aliases are represented with owner PID 0, so replacing one alias with another
  is treated as the same owner and is allowed without `--force`.
- A live process-owned route conflicts unless `--force` is used. The force path
  sends `SIGTERM` to the existing owner before replacing the route.

### Product implication

Portless proves the viability of trusted local HTTPS, `*.localhost`, framework
port injection, and HMR proxying. Our route model should keep its good loopback
default and diagnostic page, but must never silently retarget an existing alias
and must not couple route takeover to immediate process termination.

## Caddy

### Runtime evidence

- The convenience command
  `caddy reverse-proxy --from http://caddy-spike.localhost:14080 --to http://127.0.0.1:41731`
  returned HTTP 200 but listened on `*:14080`, exposing the proxy beyond
  loopback on available interfaces.
- The checked-in Caddyfile with `bind 127.0.0.1 ::1` validated successfully,
  listened only on both loopback addresses, and returned HTTP 200.
- The upstream fixture observed the preserved public Host header plus
  `X-Forwarded-For`, `X-Forwarded-Host`, and `X-Forwarded-Proto`.
- Both test runs shut down cleanly with SIGINT and exit status 0.

### Product implication

Caddy is viable as a routing engine, but its convenience defaults cannot become
our defaults. If embedded or sidecar Caddy remains an option, `port-tools` must
generate and verify explicit loopback binding and own the route-state safety
layer around it.

## Differences to carry into the product

| Requirement | Competitive evidence | `port-tools` requirement |
|---|---|---|
| Web discovery | Port Menu guesses from process; PortPeek performs one GET | staged classification with raw evidence and confidence |
| Port coverage | Port Menu drops `>=49152` | scan the complete listener set, then classify |
| App identity | Port Menu derives cwd/Git metadata | stable repo + worktree + package identity, separated from PID/port |
| Exposure | Caddy shortcut listened on all interfaces | loopback-only default with explicit exposure status |
| Alias collision | Portless aliases can silently retarget | refuse any existing-name replacement unless user reviews it |
| Missing upstream | Portless provides a useful diagnostic page | retain this pattern and add recovery context |
| Stop | competitors send a signal with limited proof | preflight target tree, graceful wait, release proof, optional force |
| Route takeover | Portless force can terminate the route owner | route conflict resolution and process termination are separate actions |

## System changes and cleanup state

Normal product testing made the following local changes:

- installed Port Menu and PortPeek in `/Applications`;
- installed Portless globally with npm;
- installed Caddy with Homebrew;
- created Portless state under `~/.portless` and trusted its local CA;
- launched disposable loopback HTTP/Vite fixtures and the Portless proxy.

Caddy has been stopped. Fixture and Portless processes remain running while the
evaluation continues. A visible Ghostty window is waiting at `sudo -v` for the
operator to type the macOS password before a true default-port 443 test; no
password is or will be handled by this repository or agent.

## Remaining evidence before closing the experience issue

- Interact with both menu-bar panels and record latency, hover/action states,
  empty/error states, keyboard access, and accidental-action risk. Port Menu's
  normal inventory state is now captured.
- Complete the real `https://<alias>.localhost` port-443 test after local
  operator authorization in Ghostty.
- Add Next.js, FastAPI, non-HTTP TCP, duplicate-worktree, and Docker fixtures.
- Exercise redirect, cookie, SSE, large upload, upstream HTTPS, and route reload
  cases.
- Measure idle CPU/memory over a fixed observation window.
- Remove the installed competitors and verify CA/state/launch-item residue when
  the evaluation is complete.
