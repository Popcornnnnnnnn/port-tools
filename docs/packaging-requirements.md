# Packaging requirements

Date: 2026-09-04  
Status: Product constraint for architecture and MVP work

## User promise

The production result is a normal macOS application: download it, move it to
Applications, open it, and use it. Initial discovery, `*.localhost` routing, and
reviewed graceful-stop behavior must work without terminal setup.

## Release constraints

- Ship one signed and notarized `.app` with all required executables and proxy
  components inside the bundle.
- Require no separately installed Python, Node.js, npm, Homebrew, Docker, Caddy,
  browser extension, or package manager.
- Require no `sudo`, trusted certificate authority, `/etc/hosts` edit, resolver
  file, or privileged port for the HTTP MVP.
- Use only loopback listeners by default and never open a LAN listener as an
  installation side effect.
- Keep mutable state under the app's macOS Application Support directory and
  logs under the appropriate Logs directory; never write beside the app bundle.
- Keep route/process-control state schemas versioned and migratable across app
  upgrades.
- Exclude evaluation fixtures, package caches, private keys, test certificates,
  test logs, and source-only dependencies from the release payload.
- Uninstall must remove launch items, helpers, sockets, routes, state, and any
  optional trust material installed by the product, with no residue outside
  clearly documented user data.

## Architecture consequences

ADR-0001 selects a native SwiftUI menu-bar app plus a bundled self-contained Go
core. The current Python scanner and Node proxy remain executable specifications
used to measure behavior; neither runtime is an end-user prerequisite. The Go
production port must meet size, signing, update, idle-resource, and
clean-uninstall targets before release.

The menu-bar UI must call a local versioned API for discovery, routing, and
process control. It must not construct shell commands or perform independent
process killing. Security decisions and revalidation remain centralized in the
bundled process-control component.

## Release verification

A release candidate is not considered open-box-ready until it passes on a clean
supported macOS account with no developer tools or package managers installed:

1. drag-copy and first launch;
2. first Web-service discovery within the PRD target;
3. route creation and removal;
4. graceful-stop confirmation on a disposable app;
5. app update with state migration;
6. uninstall and residue audit.
