# Port Tools supporting-service hierarchy QA

- Source visual truth: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-6f0f7ddb-ce13-49d8-af70-a3565cad9853.png`
- Final implementation screenshot: `/tmp/port-tools-build12-supporting-service-final.png`
- Focused implementation crop: `/tmp/port-tools-build12-supporting-service-focus-final.png`
- Multi-service expanded screenshot: `/tmp/port-tools-build12-supporting-services-expanded-final.png`
- Combined comparison: `/tmp/port-tools-build12-supporting-service-comparison-final.png`
- Source pixels: 864 x 624 at approximately 2x density
- Implementation pixels: 410 x 672 at 1x capture density
- Normalization: the 820 px-wide source menu content was cropped and resized to 410 x 312; the implementation was cropped to the same 410 x 312 region
- Content viewport: 410 x 640 pt plus the preview window title bar
- Primary state: one project, one Web app, one supporting service
- Secondary state: one project, one Web app, two expanded supporting services

## Full-view comparison evidence

The source and final build 12 were opened together in
`/tmp/port-tools-build12-supporting-service-comparison-final.png`. The source
made `Related services` look like a peer of the global Other sections because
it used the same disclosure heading, distant count capsule, and generous
vertical separation. Build 12 places the single `live-bridge` service directly
beneath the primary address with a smaller type scale, compact indentation, and
explicit `Supporting service` copy. The global Other sections remain separate.

## Focused region comparison evidence

- One supporting service is visible directly and does not require a redundant
  disclosure click.
- The row name, role, homepage status, endpoint, network state, and process age
  remain readable without becoming a second primary app.
- The details chevron is nearly hidden at rest and becomes clearer on hover.
- Clicking the row opens Service details; Back returns to the inventory.
- A temporary second 404 service in the same Git project changed the layout to a
  compact `Supporting services · 2` disclosure. Expanding it exposed both
  subordinate rows. The temporary fixture was stopped after verification.

## Required fidelity surfaces

- Fonts and typography: the primary app keeps the existing native system
  hierarchy; supporting names use 11 pt semibold and metadata uses 9 pt regular.
- Spacing and layout rhythm: the single supporting row sits directly beneath
  the address with a 1 pt section gap and nested leading inset; the larger gap
  before global Other sections remains.
- Colors and visual tokens: subordinate icons and metadata use secondary or
  tertiary system colors; no warning color, persistent card, or extra divider
  was introduced. Multi-service count contrast was increased after the first
  pass.
- Image quality and assets: no raster assets are required; visible icons are
  native SF Symbols.
- Copy and content: `Related services` becomes the relationship-specific
  `Supporting service` or `Supporting services`, and accessibility labels name
  the parent project.

## Interaction checks

- Single supporting service opens details with one click.
- Back returns from details without closing the app.
- Two or more supporting services collapse and expand as one nested group.
- Primary app link remains visible and clickable.
- Other Web endpoints and Other listeners remain independent disclosures.
- No native UI or runtime errors were observed.

## Comparison history

- Pass 1 finding [P1]: `Related services` visually appeared unrelated to the
  primary app because it reused the global section pattern.
- Fix: flattened the one-item case, moved it directly under the address, added
  explicit relationship copy, and reserved the group heading for two or more.
- Pass 2 finding [P2]: the inline multi-service count was too faint.
- Fix: raised the count from tertiary to secondary system color.
- Pass 3: final single- and multi-service screenshots were inspected; no
  actionable P0/P1/P2 hierarchy or interaction issues remain.

## Follow-up polish

- [P3] Reassess whether the small relationship icon needs slightly more resting
  contrast after several days of real menu-bar use.

final result: passed
