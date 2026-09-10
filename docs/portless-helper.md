# Port-free local address helper

## User contract

Port Tools offers port-free addresses once, on first launch. Choosing **Enable**
registers the bundled LaunchDaemon and opens **System Settings > General > Login
Items** when administrator approval is required. After approval, saved routes
open as `http://<alias>.localhost` on future launches without terminal commands
or repeated setup.

If approval is missing, the helper is unreachable, or another process owns port
80, Port Tools keeps routing through the explicit
`http://<alias>.localhost:17890` fallback. The Settings window always reports
which mode is active.

OAuth and other exact-Origin integrations may still reject an alias. For those
services, **Open original address** and **Copy original address** remain
available beside the stable route.

## Security boundary

The root LaunchDaemon:

- listens only on `127.0.0.1:80` and `[::1]:80`;
- forwards only to the fixed unprivileged Port Tools core at
  `127.0.0.1:17890`;
- rejects non-default listener or upstream arguments outside the local test
  harness;
- does not read route state or accept a configurable runtime control channel;
- keeps alias validation, route ownership, upstream selection, and TLS policy
  in the current-user core;
- is packaged under `Contents/Library/LaunchServices`, with its launchd plist
  under `Contents/Library/LaunchDaemons` for `SMAppService` registration.

The helper must be signed with the containing app, and the containing app must
be notarized before LaunchDaemon registration is treated as release evidence.
When an app update changes the helper executable, Port Tools unregisters and
re-registers the bundled service as required by `SMAppService`, retaining the
high-port route until the refreshed helper is active.

## Validation boundary

Unit and local bundle tests cover helper health identification, fixed-target
proxying, Host preservation, port-free URL publication, fallback restoration,
plist placement, and nested code signatures. A local ad-hoc build cannot prove
administrator approval or launchd activation; those require a notarized build
installed in `/Applications` and a clean-account system test.
