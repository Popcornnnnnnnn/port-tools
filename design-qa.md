# Port Tools disclosure affordance and global alignment QA

- Source visual truth 1: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-c60e4f73-cfb5-4ecd-9764-1161cb18980c.png`
- Source visual truth 2: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-3b45857b-abe5-47c7-bf42-041ffb2957bf.png`
- Default implementation screenshot: `/tmp/port-tools-build16-affordance-alignment.png`
- Expanded implementation screenshot: `/tmp/port-tools-build16-two-services-expanded.png`
- Affordance focus crop: `/tmp/port-tools-build16-affordance-focus.png`
- Other-groups focus crop: `/tmp/port-tools-build16-other-focus.png`
- Combined comparison: `/tmp/port-tools-build16-affordance-alignment-comparison.png`
- Source pixels: 818 x 190 and 878 x 346 at approximately 2x density
- Implementation pixels: 410 x 672 at 1x capture density
- Normalization: source 1 downsampled to 409 x 95; source 2 cropped to the 820 px menu region and downsampled to 410 x 173; implementation regions captured at matching 410 px width
- Content viewport: 410 x 640 pt plus the preview title bar
- Test state: three Git-backed projects; a two-background-service control was tested collapsed and expanded

## Full-view comparison evidence

Build 16 preserves build 15's compact three-line project structure. The
two-service indicator is now a quiet capsule rather than low-contrast bare
glyphs, while the one-service indicator remains compact. Both global Other
groups begin on the same text axis as project titles instead of inheriting the
old nested-section indent.

## Focused region comparison evidence

Both requested regions were inspected together in
`/tmp/port-tools-build16-affordance-alignment-comparison.png`. The service
control's resting foreground increased from 34% to 50% secondary opacity and
gained a 6.5% secondary capsule; hover/expanded state rises to 78% foreground
and 12% background. For Other groups, disclosure spacing changed from 8 pt to
0 and leading content inset from 12 pt to 0, placing label text at the primary
20 pt content axis while keeping the chevron in the left gutter.

## Required fidelity surfaces

- Fonts and typography: existing project, branch, address, Other label, and
  count typography is unchanged; the adjustment affects affordance treatment
  and alignment only.
- Spacing and layout rhythm: Other labels now align with project titles. Their
  expanded endpoint rows remain indented because those rows are true children.
- Colors and visual tokens: the service capsule uses the existing neutral
  secondary color at low opacity; no accent or warning semantics were added.
- Image quality and assets: all visible icons remain native SF Symbols; no
  raster or generated asset is required.
- Copy and content: no text changed. `2` remains a count, while its surrounding
  icon and capsule now communicate that the cluster is interactive.

## Interaction checks

- The two-service capsule exposes a named button with Collapsed state.
- Activating it reveals both supporting rows and changes accessibility state to
  Expanded.
- The one-service capsule remains a named interactive control without adding a
  repeated count.
- Other Web endpoints and Other listeners remain independently clickable after
  their alignment change.
- Expanded endpoint rows preserve their subordinate indentation.
- No native UI or runtime errors were observed.

## Findings and comparison history

- Earlier [P2]: the bare relationship glyph and `2` were too faint to read as a
  clickable control.
- Earlier [P2]: global Other labels inherited a nested disclosure inset, leaving
  an unexplained empty strip at the left.
- Fix: added a low-noise capsule and higher resting contrast to the background
  service control; added configurable disclosure spacing and aligned global
  group text to the primary content axis.
- Post-fix evidence: the normalized comparison shows the service control as an
  intentional compact button and both Other labels aligned with project titles.
  The two-service expanded state was exercised. No actionable P0/P1/P2 issue
  remains.

## Follow-up polish

- [P3] Reassess the service capsule's resting opacity after several days of
  mixed light/dark appearance use.

final result: passed
