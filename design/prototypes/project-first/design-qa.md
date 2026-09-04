# Design QA — Direction 1: Project-first control center

Date: 2026-09-04
Final result: passed

## Comparison target

- Source visual truth: `/Users/forge/Workspace/port-tools/evaluation/screenshots/01-port-menu-inventory.png`
- Implementation: `http://127.0.0.1:45123/`
- Combined comparison view: `http://127.0.0.1:45123/?qa=1`
- Browser-rendered capture: Codex in-app browser tab 2, captured from the combined comparison view on 2026-09-04
- Source pixels: 788 × 1400 at 2× density, normalized to 394 × 700 CSS px
- Implementation viewport: 394 × 700 CSS px inside the comparison iframe at 1× density
- State: light appearance, all three project groups expanded, no service detail expanded

The implementation now matches the source's roughly 394 px panel width. Detailed controls remain available only after expanding one app.

## Full-view comparison evidence

The combined browser view placed the normalized Port Menu source and live implementation side by side. The implementation preserves the source hierarchy: quiet white macOS panel, project name first, branch and age as secondary metadata, green availability indicators, restrained separators, and a vertically scannable inventory. It intentionally replaces repeated top-level project rows with worktree groups and subordinate app rows. The simplification pass removed the persistent search/filter row, footer status bar, bordered service cards, and app-level disclosure icons; explicit healthy-state pills remain because the product owner found them useful.

No P0, P1, or P2 mismatch remained after comparison. The stop-review command column was widened from 218 px to 239 px after the interaction-state review so realistic commands no longer break into unnecessarily short fragments.

## Focused-region evidence

- Inventory rows: project/worktree headings, app rows, branch, port, age, stable route, explicit Web-verified state, LAN exposure, and possibly-forgotten state were readable without collision. App rows no longer form a repetitive right-hand column of disclosure symbols.
- Web evidence modal: three evidence statements, page title, process command, and bind scope were visible in one compact sheet.
- Stable-name modal: editable slug, resulting `.localhost:4111` address, current raw address, and local-only/no-admin explanation were visible before save.
- Stop modal: PID, exact command, released listener, unaffected app count, graceful-stop behavior, and explicit destructive action were visible before confirmation.

## Required fidelity surfaces

- Fonts and typography: system UI and monospace fallbacks match the native macOS character of the source. Project names remain the strongest type; supporting metadata stays subordinate but readable. Long app names and routes truncate instead of pushing age or disclosure controls off-screen.
- Spacing and layout rhythm: 48 px project headings and 49 px app rows retain the source's compact scan rhythm. A single inset rule communicates grouping without bordered cards. The panel sizes to content up to a 700 px maximum, then scrolls.
- Colors and visual tokens: neutral whites and grays follow the source. Green is reserved for verified state; amber communicates LAN exposure and possible staleness with text, so status does not rely on color alone. Red appears only in the reviewed stop action.
- Image quality and asset fidelity: the source has no product imagery. All UI icons use one consistent Phosphor icon family; no placeholder art, emoji, handcrafted SVG, or raster substitute is present.
- Copy and content: labels describe user intent (`Name it`, `Why this is a Web app`, `Stop gracefully`) rather than raw process implementation. `5 Web apps` communicates the default scope without a permanent filter control, and prototype data is explicitly labeled.
- Accessibility: icon-only controls have accessible names, service rows are keyboard reachable, focus is visible, reduced motion is respected, and state pills include text. Desktop targets follow compact macOS control sizing.
- Responsiveness: the panel fits the 394 × 700 comparison viewport and sizes to its content; shorter viewports keep the inventory scrollable.

## Primary interactions tested

- Expand an app and reveal Open, Copy, Rename/Name, Stop, evidence, and project-folder actions.
- Open the Web-classification evidence sheet and close it.
- Claim `scanner-fixtures.localhost:4111` from an unnamed raw address and observe the updated inventory.
- Open the safe-stop preview, confirm the simulated graceful stop, observe the app count decrement, and verify the postcondition toast.
- Trigger Open, Copy, and Refresh feedback.
- Browser console errors and warnings checked: none.

## Comparison history

1. Initial comparison: the stop-review command wrapped into three uneven fragments (P2 typography and spacing).
2. Fix: reduced the impact-card label column from 93 px to 72 px, giving the exact command more horizontal room.
3. Post-fix review: the command uses the available width without changing the modal hierarchy; no actionable P0/P1/P2 finding remains.
4. Product-owner simplification feedback: the default panel felt too busy (P2 density and hierarchy).
5. Fix: removed the search/filter toolbar and footer, initially hid repetitive healthy-state pills, replaced child cards with a single inset grouping rule, reduced project/app row heights, matched the source's 394 px width, and made the panel size to content.
6. Post-fix comparison: the main scan view had one primary hierarchy and only exception states drew color. Expanded actions and all safety evidence remained intact.
7. Product-owner refinement: explicit healthy-state reminders were useful, but the repeated up/down disclosure symbols formed an unattractive right-hand column (P2 affordance and visual rhythm).
8. Fix: restored compact `Web verified` pills, removed disclosure icons from all app rows, and replaced the project-group up/down chevrons with three subtle right-facing carets that rotate only at group level.
9. Post-fix comparison: status meaning is explicit without recreating the arrow column; the row itself remains the app-detail hit target. No actionable P0/P1/P2 finding remains.

## Follow-up polish

- P3: Native SwiftUI implementation should validate the exact material blur and shadow on macOS 14 and 15 because browser backdrop rendering is only an approximation.
- P3: VoiceOver ordering and Dynamic Type behavior require validation in the eventual native app.
