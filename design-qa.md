# Port Tools compact inventory density QA

- Source visual truth: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-aab2a5f5-608e-4554-aa65-2b59b68e2e9f.png`
- Default implementation screenshot: `/tmp/port-tools-build14-compact-default.png`
- Expanded implementation screenshot: `/tmp/port-tools-build14-compact-expanded.png`
- Focused implementation crop: `/tmp/port-tools-build14-compact-focus.png`
- Combined density comparison: `/tmp/port-tools-build14-density-comparison.png`
- Source pixels: 824 x 282 at approximately 2x density
- Implementation pixels: 410 x 672 at 1x capture density
- Normalization: source downsampled to 412 x 141; implementation project region cropped and placed in a 412 x 141 comparison frame
- Content viewport: 410 x 640 pt plus the preview title bar
- Test state: two single-page projects, one background service under each; first group also tested expanded

## Full-view comparison evidence

The default build 14 screenshot shows two complete project summaries plus both
global Other groups within roughly the same vertical area previously occupied
by one project. The fixed menu frame remains unchanged so larger inventories can
still scroll without a resizing popover.

## Focused region comparison evidence

The normalized source and implementation were inspected together in
`/tmp/port-tools-build14-density-comparison.png`. The source used four visible
levels for one single-page project: title, repository context, address, and a
30 pt supporting-service disclosure. Build 14 reduces the default scan path to
three compact lines: title/status/age, primary address/edit, and a 22 pt
background-service disclosure. The repository context remains available as the
title help text instead of consuming a permanent row.

## Required fidelity surfaces

- Fonts and typography: native system fonts and the existing hierarchy remain;
  only secondary group labels were reduced by 0.5 pt and changed to medium,
  secondary styling. Primary app names and addresses retain their sizes.
- Spacing and layout rhythm: main-row vertical padding changed from 9 to 6 pt,
  internal spacing from 6 to 4 pt, background disclosures from 30 to 22 pt,
  Other disclosures from 36 to 30 pt, and project/footer gaps were tightened.
- Colors and visual tokens: the background-service label now uses the neutral
  secondary token; no new warning color, card, divider, or persistent highlight
  was introduced.
- Image quality and assets: no raster assets are required by the implementation;
  all visible icons remain native SF Symbols at their intended density.
- Copy and content: `supporting service` becomes the clearer `background
  service`; runtime age and the directly openable address remain visible because
  they support stale-server decisions. Repository URL and branch are hidden
  from the default single-page scan path.

## Interaction checks

- The primary `.localhost` address remains directly clickable.
- The pencil remains visible and opens address editing.
- `1 background service` expands and collapses without reserving a large empty
  region in the collapsed state.
- Expanded `live-bridge` still exposes its name, LAN state, homepage status,
  endpoint, and age.
- Clicking `live-bridge` opens Service details; Back returns to the inventory.
- Other Web endpoints and Other listeners remain independent disclosures.
- Accessibility exposes hidden repository context as help on the app title and
  preserves named buttons for the address, edit action, and disclosure.
- No native UI or runtime errors were observed.

## Findings and comparison history

- Earlier [P1]: the one-item supporting-service disclosure visually reserved a
  full secondary-section block and made the project feel disproportionately
  tall.
- Earlier [P2]: branch and full GitHub remote consumed a permanent line in a
  single-page project even though the app title already established identity.
- Fix: moved repository context to title help, reduced the subordinate
  disclosure to 22 pt, tightened primary and global group padding, and preserved
  only decision-critical information in the default scan path.
- Post-fix evidence: the normalized comparison shows the project summary reduced
  from about 141 pt to about 89 pt without losing its primary action, health, or
  age. Expanded, details, and Back states remain functional. No actionable
  P0/P1/P2 issue remains.

## Follow-up polish

- [P3] Reassess the neutral background-service label contrast after several days
  of real menu-bar use; its hit target is larger than its visible text.

final result: passed
