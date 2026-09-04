# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

## Product decisions for this prototype

- Present one direction at a time; do not place multiple competing concepts in the same user test.
- Use Port Menu's compact, quiet macOS panel as the visual baseline.
- Default to development Web apps, not every listening port.
- Lead with project/worktree and app identity; runtime names such as `node` belong only in evidence.
- Stable local names, Web-classification evidence, LAN exposure, and exact stop impact must be understandable from the inventory flow.
- Keep the default inventory quieter: healthy Web status is implicit, while only exceptions such as LAN exposure and possibly-forgotten state receive persistent labels. Search, filters, and detailed actions should not occupy permanent space in the main scan view.
- All data and mutations in this direction are simulated. Never connect this prototype to real process termination.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.
