# Port Tools adaptive inventory QA

- Source visual truth: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-35ceb7c8-d3de-4db1-a03e-c5019ccf5399.png`
- Implementation screenshot: `/tmp/port-tools-build10-final.png`
- Side-by-side comparison: `/tmp/port-tools-build10-comparison.png`
- Source pixels: 976 x 686
- Implementation pixels: 820 x 1344
- Implementation content viewport: 410 x 640 pt at 2x; the saved image also includes the 32 pt preview title bar
- State: one project, one directly openable Web app, Related/Other sections collapsed
- Density normalization: source scaled to 820 px width; implementation retained at 820 px width and 2x density; both top-aligned in the comparison image

## Full-view comparison evidence

The source and implementation were opened together in
`/tmp/port-tools-build10-comparison.png`. The implementation removes the
redundant project disclosure and `1 app` heading for a single-page project.
The primary URL remains visible without expanding anything. The persistent
blue action card, duplicate URL, path row, and Open/Copy/Rename button strip
are gone. Repository/branch context remains directly beneath the page name.

The source used a saved `.localhost` alias while the isolated QA runtime had no
route state and therefore displayed `127.0.0.1:4317`. This is an intentional
fixture difference, not a layout difference; the installed app keeps its real
route state.

## Focused region comparison evidence

- Primary row: title, small verified shield, age, overflow menu, directly
  clickable link, and low-emphasis edit icon fit in a compact three-line block.
- Inline edit: clicking the pencil replaces the link with an alias-prefix field,
  fixed `.localhost:17890` suffix, Save, and Cancel controls. Invalid input
  produces a red field outline and disables Save; Escape restores the link.
- Related services: the compact disclosure remains independently expandable.
- Multi-page fixture: two temporary Web pages in one Git project produced one
  static project heading and two simultaneously visible URL buttons; no project
  disclosure gated either link.
- Overflow menu: Copy address, display-name rename, project rename, local-address
  editing, detection details, Finder reveal, and project-path copy were present.

## Required fidelity surfaces

- Fonts and typography: native system fonts and existing weight hierarchy retained; singular summary copy corrected to `1 project · 1 Web app`.
- Spacing and layout rhythm: redundant parent row and expanded card removed; single-page content is flatter and shorter; Related/Other sections remain visually subordinate.
- Colors and visual tokens: persistent blue selection fill removed; blue is reserved for the actionable URL; normal verification is a small green shield.
- Image quality and assets: no raster assets are used; all icons are native SF Symbols.
- Copy and content: duplicate URL and non-working preview Stop action removed; menu labels describe their exact actions.

## Interaction checks

- URL is exposed as an accessibility button with `Open in browser` help.
- Pencil opens the inline editor and focuses/selects the alias prefix.
- Invalid alias disables Save and shows the error outline.
- Escape cancels inline editing.
- Related services expands and exposes its child service.
- Multi-page projects keep every primary link visible.
- No native UI or runtime errors were observed during the checks.

## Comparison history

- Pass 1: source showed a gated action card, duplicated address, and redundant single-item hierarchy.
- Fix: flattened the single-page hierarchy, made the URL the primary action, moved low-frequency actions to overflow, and added inline alias editing.
- Pass 2: source and build 10 were compared side by side; no actionable P0/P1/P2 design differences remain for the approved direction.

## Follow-up polish

- [P3] Re-evaluate the exact resting opacity of the pencil after several days of real menu-bar use.

final result: passed
