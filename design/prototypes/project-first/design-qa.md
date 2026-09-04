# Design QA — Direction 1: Project-first control center

Date: 2026-09-04
Final result: passed

## Comparison target

- Source visual truth: `/Users/forge/Workspace/port-tools/evaluation/screenshots/01-port-menu-inventory.png`
- Implementation: `http://127.0.0.1:45123/`
- Combined comparison view: `http://127.0.0.1:45123/?qa=1`
- Browser-rendered capture: Codex in-app browser tab 1, captured from the combined comparison view on 2026-09-04
- Source pixels: 788 × 1400 at 2× density, normalized to 394 × 700 CSS px
- Implementation viewport: 430 × 720 CSS px inside the comparison iframe at 1× density
- State: light appearance, all three project groups expanded, no service detail expanded

The 430 px implementation width is an intentional product divergence from the roughly 394 px source panel. It preserves the source's menu-bar density while providing enough room for app identity, status, stable routes, and evidence without truncating the primary task.

## Full-view comparison evidence

The combined browser view placed the normalized Port Menu source and live implementation side by side. The implementation preserves the source hierarchy: quiet white macOS panel, project name first, branch and age as secondary metadata, green availability indicators, restrained separators, and a vertically scannable inventory. It intentionally replaces repeated top-level project rows with worktree groups and subordinate app rows.

No P0, P1, or P2 mismatch remained after comparison. The stop-review command column was widened from 218 px to 239 px after the interaction-state review so realistic commands no longer break into unnecessarily short fragments.

## Focused-region evidence

- Inventory rows: project/worktree headings, app rows, branch, port, age, stable route, Web status, LAN exposure, and possibly-forgotten state were readable without collision.
- Web evidence modal: three evidence statements, page title, process command, and bind scope were visible in one compact sheet.
- Stable-name modal: editable slug, resulting `.localhost:4111` address, current raw address, and local-only/no-admin explanation were visible before save.
- Stop modal: PID, exact command, released listener, unaffected app count, graceful-stop behavior, and explicit destructive action were visible before confirmation.

## Required fidelity surfaces

- Fonts and typography: system UI and monospace fallbacks match the native macOS character of the source. Project names remain the strongest type; supporting metadata stays subordinate but readable. Long app names and routes truncate instead of pushing age or disclosure controls off-screen.
- Spacing and layout rhythm: 55 px group/app rows retain the source's scan rhythm. Nested service cards make grouping explicit without turning the panel into a dashboard. Footer controls remain visible while inventory content scrolls.
- Colors and visual tokens: neutral whites and grays follow the source. Green is reserved for verified state; amber communicates LAN exposure and possible staleness with text, so status does not rely on color alone. Red appears only in the reviewed stop action.
- Image quality and asset fidelity: the source has no product imagery. All UI icons use one consistent Phosphor icon family; no placeholder art, emoji, handcrafted SVG, or raster substitute is present.
- Copy and content: labels describe user intent (`Web apps`, `Name it`, `Why this is a Web app`, `Stop gracefully`) rather than raw process implementation. Prototype data is explicitly labeled.
- Accessibility: icon-only controls have accessible names, service rows are keyboard reachable, focus is visible, reduced motion is respected, and state pills include text. Desktop targets follow compact macOS control sizing.
- Responsiveness: the panel fits the 430 × 720 comparison viewport without hiding persistent controls; narrower viewports switch to an edge-aligned app panel and keep the inventory scrollable.

## Primary interactions tested

- Expand an app and reveal Open, Copy, Rename/Name, Stop, evidence, and project-folder actions.
- Open the Web-classification evidence sheet and close it.
- Claim `scanner-fixtures.localhost:4111` from an unnamed raw address and observe the updated inventory.
- Open the safe-stop preview, confirm the simulated graceful stop, observe the app count decrement, and verify the postcondition toast.
- Search for a missing app, observe the empty state, and clear the filter.
- Trigger Open, Copy, and Refresh feedback.
- Browser console errors and warnings checked: none.

## Comparison history

1. Initial comparison: the stop-review command wrapped into three uneven fragments (P2 typography and spacing).
2. Fix: reduced the impact-card label column from 93 px to 72 px, giving the exact command more horizontal room.
3. Post-fix review: the command uses the available width without changing the modal hierarchy; no actionable P0/P1/P2 finding remains.

## Follow-up polish

- P3: Native SwiftUI implementation should validate the exact material blur and shadow on macOS 14 and 15 because browser backdrop rendering is only an approximation.
- P3: VoiceOver ordering and Dynamic Type behavior require validation in the eventual native app.
