# Direction 1 — Project-first control center

Status: Ready for product-owner experience
Date: 2026-09-04

## Hypothesis

A developer remembers a project or app, not a runtime process or arbitrary port. The menu should therefore start with project/worktree identity, keep multiple Web apps visible inside that group, and defer process details until the user asks for evidence or prepares a stop.

## Visual baseline

This direction deliberately inherits Port Menu's compact native panel, restrained decoration, strong project names, and quiet branch/port/age metadata. It differs in four visible ways:

1. repeated repository rows become one worktree group with quiet, inset app rows;
2. the default view contains only development Web apps;
3. stable local names and exposure/staleness states are visible in place;
4. destructive actions appear only after selecting an app and reviewing impact.

## Core product flow covered

- Rediscover work by project, branch, app name, route, raw port, and age.
- Understand why a listener is considered Web and whether it is LAN-exposed.
- Claim or change a stable `<name>.localhost:4111` route.
- Review the exact PID, command, released listener, and unaffected apps before a simulated graceful stop.

## Prototype boundary

The browser prototype is a product-flow artifact, not the shipping runtime. Its data is intentionally realistic but fixed, and every mutation is simulated. The selected production architecture remains a native SwiftUI `MenuBarExtra` backed by the bundled Go core; this prototype is designed so its hierarchy and flows can be ported to that shell without adding browser-runtime dependencies to the final app.

## Experience questions

- Does grouping make the list faster to understand than Port Menu's repeated rows?
- Healthy apps retain a compact `Web verified` label; LAN exposure and possibly-forgotten states remain more prominent exceptions.
- App rows open directly without a repeated disclosure glyph; only project groups have a subtle rotating caret.
- Are stable routes prominent enough to replace raw port memory?
- Does the stop preview feel safe without becoming annoying?
- Does the 394 px panel width now feel compact enough for a menu-bar utility?
