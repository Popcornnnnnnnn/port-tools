# Port Tools project-source and background-service QA

- Source visual truth: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-93fe28ae-fe4f-4c05-b065-16e79a553298.png`
- Default implementation screenshot: `/tmp/port-tools-build15-project-links-default.png`
- Expanded implementation screenshot: `/tmp/port-tools-build15-background-expanded.png`
- Focused implementation crop: `/tmp/port-tools-build15-project-list-focus.png`
- Combined comparison: `/tmp/port-tools-build15-project-links-comparison.png`
- Source pixels: 840 x 672 at approximately 2x density
- Implementation pixels: 410 x 672 at 1x capture density
- Normalization: source downsampled to 420 x 336; implementation inventory region cropped to 410 x 320 and placed in a matching 420 x 336 frame
- Content viewport: 410 x 640 pt plus the preview title bar
- Test state: three single-page Git worktrees; zero, one, and two background-service indicators were all visible

## Full-view comparison evidence

The default build 15 screenshot shows three projects, their branch/repository
identity, their primary local address, and both global Other groups without the
three repeated background-service text rows. A project with no background
service shows no indicator; one service shows only the relationship icon; two
services show the icon plus `2`.

## Focused region comparison evidence

The normalized before/after states were inspected together in
`/tmp/port-tools-build15-project-links-comparison.png`. The source spent a full
row repeating `1 background service` while omitting the Git source. Build 15
uses that vertical budget for `branch · owner/repository`, attaches the service
indicator to the title, and keeps the local page address as a separate blue
action. The resulting project blocks are denser while differentiating otherwise
similar worktrees.

## Required fidelity surfaces

- Fonts and typography: project titles remain 13 pt semibold; Git context is
  9.5 pt secondary text; addresses remain 10 pt monospaced. The title's external
  link icon uses a fixed 9 pt slot so hover does not shift neighboring controls.
- Spacing and layout rhythm: background services no longer reserve a collapsed
  row. The restored Git line reuses the compact 4 pt internal rhythm, leaving
  each project at three meaningful lines.
- Colors and visual tokens: project titles remain label-colored instead of blue;
  only the local page address uses the accent color. Repository-link affordance
  appears through hover underline/external-link disclosure. Background-service
  indicators use a neutral secondary token.
- Image quality and assets: no raster assets are required by the implementation;
  branch, external-link, verification, relationship, address, and edit icons are
  native SF Symbols.
- Copy and content: full `github.com/` prefixes are omitted while owner/repository
  identity remains. Background count text is suppressed for one service and
  appears only for two or more.

## Interaction checks

- Accessibility exposes each remote-backed project title as an `open current
  repository branch` button.
- GitHub destination construction was verified for `main` and slash-containing
  worktree branches; the system has an HTTPS handler.
- The local `.localhost` or loopback address remains a separate button and still
  opens the running page.
- The one-service relationship icon expands `live-bridge`; its accessibility
  value changes from Collapsed to Expanded.
- The two-service indicator exposes its numeric count and remains collapsed by
  default.
- Expanded supporting rows still open Service details, and Back behavior is
  unchanged from the previously verified flow.
- The title was not activated during QA to avoid opening an unsolicited tab in
  the user's default browser; URL generation, target semantics, accessible
  action, and installed HTTPS handler were checked independently.
- No native UI or runtime errors were observed.

## Findings and comparison history

- Earlier [P1]: every project repeated the same `1 background service` text,
  creating noise without adding identity.
- Earlier [P2]: hiding branch/repository context made worktrees with similar
  names difficult to distinguish.
- Fix: moved background-service access into the title row, suppressed the count
  for one service, restored compact Git context, and made remote-backed titles
  open their current repository branch.
- Post-fix evidence: the combined comparison shows all three repeated rows
  removed and all three Git sources restored without increasing the overall
  inventory height. The one-service expansion and the two-service count state
  were exercised. No actionable P0/P1/P2 issue remains.

## Follow-up polish

- [P3] Validate the title hover underline and external-link reveal during normal
  use; the code prevents layout shift, but QA intentionally did not launch the
  user's external browser.
- [P3] Reassess whether the one-service icon needs slightly higher resting
  contrast after several days of use.

final result: passed
