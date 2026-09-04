# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

## Product decisions for this prototype

- Present one direction at a time; do not place multiple competing concepts in the same user test.
- Use Port Menu's compact, quiet macOS panel as the visual baseline.
- Default to development Web apps, not every listening port.
- Lead with project/worktree and app identity; runtime names such as `node` belong only in evidence.
- Stable local names, Web-classification evidence, LAN exposure, and exact stop impact must be understandable from the inventory flow.
- Keep the default inventory quiet while retaining an explicit `Web verified` pill for healthy apps. Search, filters, and detailed actions should not occupy permanent space in the main scan view.
- Combine the project-first inventory with search-first discovery. Search opens from the header or with Command-K, matches project, app, port, branch, path, and remote, and temporarily expands matching projects.
- Group as project/worktree, then application manifest, then live service. Hide the application heading when the project contains only one application.
- Avoid a repeated right-side disclosure column. The entire project row toggles expansion, with one subtle leading disclosure indicator; the right side contains only a service or attention summary.
- Read real scanner inventory in local development. Opening and copying real addresses are enabled; naming and stopping remain clearly labeled, persistent browser simulations and must never terminate a real process.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.
