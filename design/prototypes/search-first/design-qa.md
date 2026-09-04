# Design QA — Direction 3: Search-first command launcher

## Evidence

- Source visual truth: `/Users/forge/Workspace/port-tools/design/references/direction-3-search-first.png` (`1086 × 1448` px).
- Normalized source crop: `/Users/forge/Workspace/port-tools/design/prototypes/search-first/qa-source-cropped.png` (`968 × 1330` px), cropped to the popover border and rendered into a `420 × 560` CSS slot.
- Browser-rendered implementation: `/Users/forge/Workspace/port-tools/design/prototypes/search-first/implementation-main.jpg` (`608 × 901` px browser capture).
- Focused interaction evidence: `/Users/forge/Workspace/port-tools/design/prototypes/search-first/implementation-evidence.jpg` (`608 × 901` px browser capture).
- Combined comparison: `/Users/forge/Workspace/port-tools/design/prototypes/search-first/qa-comparison.jpg` (`608 × 901` px browser capture).
- Intended component viewport: `420 × 560` CSS px, light theme, empty search, `Menu prototype` selected.
- Density normalization: the generated source was cropped to its panel edge and both source and implementation were rendered in equal `420 × 560` CSS slots. The combined in-app browser view scales both slots to `64%` only to fit the available width.

## Findings

No actionable P0, P1, or P2 differences were found in the first normalized comparison.

- Fonts and typography: both views use the macOS system sans-serif hierarchy, compact metadata, semibold app names, and quiet keyboard hints. The implementation preserves truncation for long repository paths without hiding the app identity or status.
- Spacing and layout rhythm: title, search field, selected result, attached action strip, four remaining rows, and keyboard footer align with the target at the same component size. The implementation uses slightly crisper separators, which is acceptable for a live control.
- Colors and visual tokens: the focused blue search border, pale blue selection, green verified states, amber attention states, white surface, and neutral backdrop match the source hierarchy.
- Image quality and asset fidelity: the interface has no photo, illustration, logo, or decorative raster assets. Runtime controls use Phosphor icons instead of handcrafted SVG, CSS drawings, emoji, or text-symbol approximations.
- Copy and content: the five apps, addresses, project and branch evidence, ports, ages, status language, actions, search placeholder, count, and footer shortcuts match the selected visual target.

## Focused Region Comparison

The selected-row action strip is readable in the full comparison and matches the source anatomy closely, so it did not require a separate crop. The evidence modal is not depicted in the source; its browser capture was inspected separately to verify typography, spacing, icon treatment, focus, and modal contrast remain consistent with the selected direction.

## Comparison History

### Iteration 1 — passed

- The normalized side-by-side evidence showed matching component dimensions, information hierarchy, row count, selected state, action-strip placement, semantic colors, and footer position.
- No P0/P1/P2 visual fixes were required after this comparison.
- Residual P3: implementation metadata and status badges are marginally smaller and sharper than the generated raster. They remain readable at the actual `420 × 560` menu size and help the five results fit without clipping.

## Primary Interactions Tested

- Searched for port `4319`; only `WebRTC receiver` remained.
- Pressed Return and observed open feedback for `127.0.0.1:4319`.
- Cleared search with Escape and changed selection with Arrow Down.
- Opened classification evidence from the inline `Why Web?` action.
- Renamed `station-control.localhost:4111` to `station-ui.localhost:4111` and observed the result update.
- Reviewed the exact `stationControl` PID and command, completed the simulated graceful stop, and verified the app count changed from five to four; reload restored fixture data.
- Checked browser console warnings and errors: none.

## Implementation Checklist

- [x] Same-size source and implementation comparison.
- [x] Search filters by app, address, project, branch, and port.
- [x] Arrow keys and Return support the primary keyboard flow.
- [x] Selected-row actions work without disclosure arrows.
- [x] Rename, evidence, and safe-stop review flows work.
- [x] Mock data and simulated mutations are labeled `DEMO`.
- [x] Browser console is clean.

final result: passed
