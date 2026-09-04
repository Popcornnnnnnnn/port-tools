# Design QA — Three-direction comparison harness

## Evidence

- Source specification: `/Users/forge/Workspace/port-tools/design/prototypes/comparison/comparison-spec.md`.
- Source Direction 1: `/Users/forge/Workspace/port-tools/design/prototypes/comparison/source-direction1.jpg` (`608 × 901` px browser capture).
- Source Direction 2: `/Users/forge/Workspace/port-tools/design/prototypes/attention-first/implementation-main.jpg` (`608 × 901` px browser capture).
- Source Direction 3: `/Users/forge/Workspace/port-tools/design/prototypes/search-first/implementation-main.jpg` (`608 × 901` px browser capture).
- Rendered comparison page: `/Users/forge/Workspace/port-tools/design/prototypes/comparison/implementation-comparison.jpg` (`608 × 901` px browser capture).
- Browser viewport: `608 × 901` px, light theme, Direction 3 selected in the full-size preview.
- Density normalization: all three overview frames render their live prototype at a common `29%` scale in the narrow in-app browser layout. The selected full preview retains its prototype's native CSS dimensions and is vertically scrollable.

## Findings

No actionable P0, P1, or P2 differences remain between the comparison specification and the rendered page.

- Fonts and typography: the wrapper uses the same macOS system family as all three prototypes, with a clear page title, concise direction labels, quiet trade-offs, and readable full-size preview copy. Thumbnail text is intentionally overview-only.
- Spacing and layout rhythm: all three thumbnails fit on one row at the actual in-app browser width; equal card widths and aligned headings make density differences visible. The enlarged preview starts immediately below and remains usable through page scrolling.
- Colors and visual tokens: neutral gray wrapper surfaces do not compete with the embedded prototypes. Blue selection and green live status are restrained and consistent with the existing prototypes.
- Image quality and asset fidelity: the comparison uses the actual live prototype URLs rather than raster approximations, placeholders, custom drawings, or restyled recreations.
- Copy and content: each direction has a neutral framing label, one-line usage model, and one-line trade-off. No winner is declared.

## Full-view and Focused Comparison Evidence

The browser capture shows all three live prototypes together in one row and Direction 3 at full size below. The thumbnail row itself is the combined comparison input: it places the three source implementations at a common visual scale inside the rendered comparison harness. A separate detail crop was unnecessary because selecting a direction exposes its unscaled interactive version below.

## Comparison History

### Iteration 1 — passed

- All three live frames loaded without missing content.
- Direction cards aligned at the narrow browser breakpoint and made differences in hierarchy, density, and menu height visible.
- No P0/P1/P2 visual fix was required after the first browser capture.
- Residual P3: thumbnail copy is too small for detailed reading at 608 px width, by design; the full-size preview provides readable inspection immediately below.

## Primary Interactions Tested

- Selected Direction 1 and verified the full preview heading and iframe switched to Project-first.
- Selected Direction 2 and verified the full preview switched to Attention-first.
- Selected Direction 3 and verified the full preview switched back to Search-first.
- Confirmed all three thumbnail iframes and the full-size iframe loaded their complete accessibility trees.
- Checked browser console warnings and errors: none.

## Implementation Checklist

- [x] Three directions visible together.
- [x] Equal thumbnail comparison scale at the actual browser width.
- [x] One full-size interactive preview.
- [x] Direction switcher works for all three prototypes.
- [x] Original prototype UIs remain unchanged.
- [x] Browser console is clean.

final result: passed
