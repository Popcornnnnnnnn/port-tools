# Direction 3 — Search-first command launcher

## Hypothesis

The fastest way to return to local development work is not browsing a complete inventory. It is typing the fragment already in mind—an app name, project, port, or local domain—and opening the best match immediately.

## Information hierarchy

1. A focused search field is the primary control.
2. One selected result exposes direct Open, Copy, Rename, Stop, and classification-evidence actions.
3. Health, exposure, project, branch, port, and age remain visible but secondary.

## Interaction model

- Search filters across app name, address, project, branch, and port.
- Arrow keys change selection; Return opens; Escape clears and leaves search.
- Clicking a row changes selection without navigating away.
- Actions expand inline only for the selected result—no disclosure glyphs or project accordions.
- Rename and safe stop retain explicit review flows.
- Fixed sample data and all mutations are clearly marked as simulated.

## Trade-off

This direction is fastest when the user remembers any identifying fragment, but it is weaker than Direction 2 for passive monitoring and spotting every exception at a glance.
