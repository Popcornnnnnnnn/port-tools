# Port Tools supporting-service default-collapse QA

- Source visual truth: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-6f0f7ddb-ce13-49d8-af70-a3565cad9853.png`
- Default collapsed screenshot: `/tmp/port-tools-build13-supporting-collapsed.png`
- Expanded screenshot: `/tmp/port-tools-build13-supporting-expanded.png`
- Combined comparison: `/tmp/port-tools-build13-supporting-comparison.png`
- Source pixels: 864 x 624 at approximately 2x density
- Implementation pixels: 410 x 672 at 1x capture density
- Content viewport: 410 x 640 pt plus the preview window title bar
- Test state: one project, one primary Web app, one supporting service

## Comparison evidence

The source, collapsed build 13, and expanded build 13 were inspected together in
`/tmp/port-tools-build13-supporting-comparison.png`. The source used a generic
`Related services` row that could be mistaken for a peer of the global Other
sections. Build 13 changes this to a relationship-specific `1 supporting
service` row, places it immediately below the primary app address, and keeps it
collapsed until requested. Expansion reveals `live-bridge` as a subordinate
background service rather than a second app.

## Required fidelity surfaces

- Fonts and typography: the primary app retains the established native system
  hierarchy; the supporting group and service remain deliberately smaller.
- Spacing and layout rhythm: the group is nested under the primary app with a
  tighter inset and spacing than the global Other sections.
- Colors and visual tokens: the disclosure affordance is quiet at rest and no
  warning color, persistent card, or extra divider was introduced.
- Image quality and assets: all icons remain native SF Symbols; no raster assets
  are required by the implementation.
- Copy and content: the new label explicitly states the relationship and count;
  the expanded service says `Supporting service` and `No homepage`.

## Interaction checks

- Default launch keeps `live-bridge` folded under `1 supporting service`.
- Clicking the supporting-service group reveals the `live-bridge` row.
- Clicking `live-bridge` opens Service details.
- Back returns from Service details to the inventory instead of closing the app.
- The primary app link remains visible and directly clickable in both states.
- Other Web endpoints and Other listeners remain independent disclosures.
- Accessibility labels identify `live-bridge` as a supporting service for its
  parent project.
- No native UI or runtime errors were observed.

## Comparison history

- Build 12 clarified the visual relationship by using subordinate styling and
  explicit supporting-service copy, but displayed the one-item case by default.
- User feedback requested that the background `live-bridge` service remain
  available without occupying the normal primary-app scan path.
- Build 13 applies the same compact disclosure behavior to one or many
  supporting services and preserves one-click access after expansion.
- Final collapsed, expanded, details, and Back states were exercised against
  the live Phone 3D UI Studio processes; no actionable P0/P1/P2 issue remains.

## Follow-up polish

- [P3] Reassess the resting disclosure contrast after several days of real
  menu-bar use.

final result: passed
