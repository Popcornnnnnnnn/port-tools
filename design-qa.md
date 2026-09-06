# Design QA — build 17 overlay scrollbar

## Evidence

- Source visual truth: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-d22c95bb-7607-44fc-bda6-d9137e482d2b.png`
- Collapsed implementation: `/tmp/port-tools-build17-collapsed.png`
- Expanded idle implementation: `/tmp/port-tools-build17-expanded-idle.png`
- Scrolled implementation: `/tmp/port-tools-build17-scrolling.png`
- Normalized comparison: `/tmp/port-tools-build17-scrollbar-comparison.png`
- State: `Other Web endpoints` expanded in the light appearance.

## Normalization

- Source: 832 × 1276 px at 2× density, representing approximately a 416 × 638 pt menu panel.
- Implementation capture: 956 × 1480 px including the native preview-window shadow at 2× density.
- Compared implementation crop: 820 × 1282 px, representing the 410 × 641 pt app content area.
- CSS size/device scale factor: not applicable; this is a native SwiftUI/AppKit application.
- The comparison removes the preview title bar and outer shadow. The remaining 6 pt width difference is the existing preview-vs-menu-panel framing, not a scrollbar gutter.

## Findings

- No actionable P0/P1/P2 findings remain.
- The build 16/source state used a persistent, dark scrollbar approximately 11 pt wide and reserved a right-side gutter.
- Build 17 uses the native overlay scroller. At rest it is fully hidden; during the CUA scroll action it appeared as a narrow translucent indicator over the right edge; after the native fade delay it disappeared again.
- Expanding `Other Web endpoints` no longer changes the horizontal bounds of project rows, section backgrounds, counts, or the footer.

## Required fidelity surfaces

- Fonts and typography: unchanged from the accepted build; hierarchy, weight, truncation, and monospaced endpoint text remain stable.
- Spacing and layout rhythm: project and endpoint geometry remains stable across collapsed, expanded, and scrolled states; no width is reserved for the scroller.
- Colors and visual tokens: the persistent dark track is removed; the active scroller uses the native translucent macOS overlay treatment.
- Image quality and asset fidelity: no raster or custom visual assets are involved; existing SF Symbols remain unchanged.
- Copy and content: unchanged; live endpoint data and disclosure counts remain intact.

## Interaction checks

- `Other Web endpoints` expands and collapses without horizontal layout movement.
- The scroll position can move through the expanded endpoint list.
- The vertical indicator is visible only during native scroll activity and auto-hides when idle.
- The footer stays fixed while the inventory scrolls.
- The same overlay/autohide policy is applied to the service-detail scroll view.

## Comparison history

1. Initial P1: the expanded list showed a thick, persistent scrollbar that visually dominated the panel and changed available content width.
2. Fix: configured both SwiftUI scroll views through their enclosing `NSScrollView` with `.overlay`, `autohidesScrollers = true`, and `.small` vertical-scroller control size.
3. Post-fix evidence: the normalized side-by-side comparison shows the expanded idle state without a gutter; the live CUA scroll frame showed the compact overlay indicator, and the later scrolled capture confirms it faded away.

Focused-region comparison was not needed because the affected surface is the full-height right edge and the full-view normalized comparison shows both the scrollbar and layout bounds at readable resolution.

final result: passed
