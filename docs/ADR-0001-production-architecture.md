# ADR-0001: macOS production architecture

Date: 2026-09-04  
Status: Accepted for MVP implementation

## Decision

Build a native SwiftUI menu-bar application backed by one bundled Go core
executable. Distribute both inside one signed and notarized macOS `.app`.

- **UI:** SwiftUI `MenuBarExtra` using window style, with AppKit only where
  native menu/window behavior requires it.
- **Core language:** Go, compiled as a self-contained arm64 executable for the
  initial release and universal when x86_64 support is added.
- **Core ownership:** listener discovery, protocol probing, project/application
  identity, route state, safe-stop policy, signal delivery, and listener-release
  verification all remain inside the core. The UI never constructs shell or
  `kill` commands.
- **Proxy engine:** Go standard-library HTTP server and
  `net/http/httputil.ReverseProxy`, behind an internal route-engine interface.
  Do not ship Portless, Node.js, or Caddy in the first implementation.
- **Local API:** versioned JSON over a Unix-domain socket with mode `0600`.
- **Default privilege:** current user only, high unprivileged ports, IPv4/IPv6
  loopback only, no trusted CA, no hosts/resolver edits, and no privileged helper.
- **Distribution:** direct Developer ID distribution with Hardened Runtime and
  notarization. Mac App Store distribution is deferred.

## Why this fits the product

Apple's `MenuBarExtra` is the native persistent menu-bar scene and its window
style supports the richer inventory panel this product needs. The existing
Port Menu evaluation also showed that a native menu-bar surface feels right,
while its raw-process rows and unsafe kill behavior are the gaps to fix.

Go keeps the stateful scanner, proxy, and process-control policy in one
concurrency-friendly executable. Its standard reverse proxy recognizes
streaming responses and flushes them immediately, reducing the amount of
custom transport machinery. A compiled Go core has no end-user Go dependency.

The UI/core split makes security review clearer and keeps a future CLI or test
harness from duplicating privileged decisions. It also allows the UI to be
replaced without rewriting process identity and lifecycle policy.

## Measured packaging spike

The committed spike sources build a real arm64 `.app` containing a SwiftUI
menu-bar executable and a Go core in `Contents/Helpers`.

| Check | Result |
|---|---:|
| Complete app bundle payload | 5,782,167 bytes |
| Bundled Go core | 5,617,680 bytes |
| SwiftUI executable | 161,152 bytes |
| Architectures | arm64 Mach-O for both executables |
| Non-system dynamic dependencies | none observed |
| Nested then outer ad-hoc signature verification | pass |
| Menu-bar process launch | pass |
| Core self-test from inside the bundle | pass |
| Unix socket permissions | `0600` |
| `GET /v1/health` and `/v1/capabilities` | pass |
| Runtime prerequisite on test account | none after build |

This proves bundle shape, nested-code signing order, native launch, and local API
transport. It does **not** prove Developer ID notarization or the Go production
scanner/proxy port; those remain implementation acceptance gates.

The build used an official Go 1.26.5 arm64 archive whose SHA-256 matched the
published value. The toolchain lived only in a temporary directory and was
moved to Trash with the generated app after measurement; it was never installed
system-wide.

## Component boundaries

```text
Port Tools.app
├── SwiftUI menu-bar UI
│   ├── renders inventory and evidence
│   ├── requests route and stop operations
│   └── owns user confirmations
└── bundled port-tools-core
    ├── scanner and protocol probes
    ├── repository/worktree/application identity
    ├── route registry and reverse proxy
    ├── safe-stop planning and execution
    └── versioned Unix-socket API
```

The app supervises the core during MVP. “Open at Login” launches the main app
through `SMAppService`; a persistent LaunchAgent or privileged daemon is not
introduced initially. The core must exit and remove its socket/listeners when
the owning app exits unexpectedly or stops sending its supervision heartbeat.

## Local API contract

The initial API surface should include:

- `GET /v1/health` and `GET /v1/capabilities`;
- `GET /v1/services` and `GET /v1/services/{id}`;
- `GET /v1/events` for inventory/route changes;
- `PUT /v1/routes/{alias}` and `DELETE /v1/routes/{alias}`;
- `POST /v1/services/{id}/stop-plan` returning an identity-bound plan token;
- `POST /v1/services/{id}/graceful-stop` requiring that fresh token.

Every mutation returns the observed postcondition, not merely command success.
Route writes use atomic replacement. Stop-plan tokens bind the PID, start time,
project/application roots, descendant set, and expected listeners so a stale UI
confirmation cannot target a changed process.

Mutable state belongs under `~/Library/Application Support/Port Tools/`. Logs
belong under `~/Library/Logs/Port Tools/`. The Unix socket lives in a private
runtime subdirectory and is recreated with owner-only permissions.

## Proxy decision and fallback

The Node transport spike passed 20/20 compatibility checks and a 900-second
Vite/Next HMR endurance run, demonstrating that the required surface is small
enough to specify. The Go implementation must pass that identical suite before
it replaces the spike.

Use Caddy as the pre-decided fallback behind the route-engine interface if the
Go port cannot pass WebSocket/HMR, SSE, streaming, redirect, upload, HTTPS
upstream, atomic reload, and diagnostic behavior without expanding custom code
substantially. Caddy is not the first choice because it adds another bundled
process/config surface and its automatic HTTPS behavior can create CA trust and
ports 80/443 side effects unless explicitly disabled. Its zero-downtime config
API and proven proxy behavior make reversal practical.

Portless is not a production dependency: it requires a Node distribution and
the evaluation found trust-store residue after its own cleanup reported
success.

## Alternatives considered

| Alternative | Why not selected | Reversal cost |
|---|---|---|
| SwiftUI + Rust core | Strong binary and safety properties, but no standard reverse proxy, more third-party transport code, and no current local toolchain | Medium; Unix API and schemas remain reusable |
| Tauri/Rust | Can bundle sidecars, but adds a WebView/frontend permission layer to a macOS-only menu utility and weakens native iteration | High for UI, medium for core |
| All Swift | Simplest toolchain and signing, but the proxy/server and cross-process test surface would require more custom networking work | Medium; SwiftUI remains unchanged |
| SwiftUI + bundled Caddy | Most mature proxy and atomic reload API, but larger/more complex nested process and dangerous HTTPS defaults | Low for proxy only because of route-engine boundary |
| SwiftUI + bundled Portless/Node | Reuses naming UX, but runtime size, npm supply chain, CA/hosts behavior, and observed cleanup residue conflict with the product promise | High and not recommended |

## Signing, updates, and sandbox boundary

Sign nested executables before signing the outer app. Release builds enable
Hardened Runtime, use a Developer ID Application certificate, submit with
`notarytool`, and staple the result. The ad-hoc spike signature is only local
evidence.

The first release is direct-download rather than Mac App Store. Apple requires
App Sandbox for App Store distribution, whereas direct notarized distribution
requires Hardened Runtime and makes sandboxing optional. Whether process
discovery can meet the product contract inside App Sandbox remains unproven.

The updater is a separate implementation choice, but updates must verify a
signature, replace the entire app atomically, migrate versioned state, and never
download executable plug-ins at runtime.

## Port-free HTTP helper

The app bundles a minimal LaunchDaemon registered through `SMAppService`. After
one administrator approval in System Settings, it owns only IPv4 and IPv6
loopback port 80 and forwards HTTP to the current-user Go core on port 17890.
The daemon holds no route registry and accepts no configurable upstream target;
Host-based route ownership remains in the unprivileged core. When the daemon is
not approved, cannot start, or port 80 is occupied, the app publishes the
explicit `:17890` fallback.

The helper and its plist remain inside the signed app bundle. **Reset Local Data
and Quit** unregisters the daemon before removing local Port Tools state. A
future polished HTTPS mode remains a separate owner-approved design that:

1. explains why trust is requested;
2. inventories every certificate, key, helper, listener, and state path;
3. installs the narrowest possible authority through an auditable native flow;
4. removes it by exact identity and verifies absence during uninstall.

No architecture work may silently activate Caddy automatic HTTPS or introduce
certificate trust before that gate.

## Required implementation gates

1. Port the scanner/identity fixtures to the Go core and preserve 14/14 results.
2. Port the route matrix and preserve 20/20 plus 900-second HMR endurance.
3. Port safe-stop and preserve dry-run, fixture SIGTERM, exclusion, and release
   verification evidence.
4. Build a signed nested-code `.app` in CI and run it on a clean macOS account
   with no Go, Python, Node, or package manager.
5. Measure idle CPU, resident memory, app size, launch time, and first scan.
6. Verify crash cleanup, update/state migration, and uninstall residue.

## Primary references

- Apple `MenuBarExtra`: <https://developer.apple.com/documentation/swiftui/menubarextra>
- Apple `SMAppService`: <https://developer.apple.com/documentation/servicemanagement/smappservice>
- Apple Hardened Runtime: <https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime>
- Apple notarization: <https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>
- Go `httputil.ReverseProxy`: <https://pkg.go.dev/net/http/httputil>
- Caddy configuration API: <https://caddyserver.com/docs/api>
- Caddy automatic HTTPS: <https://caddyserver.com/docs/automatic-https>
- Tauri external binaries: <https://v2.tauri.app/develop/sidecar/>
