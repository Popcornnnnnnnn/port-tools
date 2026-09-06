# Design QA — build 18 transient scroll indicator

## Evidence

- Source visual truth: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-d22c95bb-7607-44fc-bda6-d9137e482d2b.png`
- Scrolling implementation: `/tmp/port-tools-build18-scrolling.png`
- One-second idle implementation: `/tmp/port-tools-build18-idle.png`
- Normalized three-state comparison: `/tmp/port-tools-build18-scrollbar-comparison.png`
- State: `Other Web endpoints` expanded in the light appearance.

## Normalization

- Source: 832 × 1276 px at 2× density, representing approximately a 416 × 638 pt menu panel.
- Implementation captures: 956 × 1480 px including the native preview-window shadow at 2× density.
- Compared implementation crops: 820 × 1282 px, representing the 410 × 641 pt app content area.
- CSS size/device scale factor: not applicable; this is a native SwiftUI/AppKit application.
- The comparison removes the preview title bar and outer shadow. Live endpoint counts and ages changed during the test and are not visual regressions.

## Findings

- No actionable P0/P1/P2 findings remain in build 18.
- The supplied/build 17 state shows a persistent dark native scrollbar and a reserved right gutter.
- Build 18 removes the native scroller from the accessibility hierarchy and layout. A 3 pt translucent custom indicator overlays the right edge during a real scroll gesture, then is absent in the one-second idle capture.
- Project rows, section backgrounds, endpoint text, counts, and footer retain identical horizontal bounds between scrolling and idle states.

## Required fidelity surfaces

- Fonts and typography: unchanged from the accepted interface; hierarchy, weights, truncation, and monospaced endpoint text remain stable.
- Spacing and layout rhythm: no scrollbar gutter exists in either build 18 state; overlay appearance does not change available row width.
- Colors and visual tokens: the active indicator uses secondary foreground at 28% opacity and has no track; the idle state contains no scrollbar pixels.
- Image quality and asset fidelity: no raster or custom product assets are involved; existing SF Symbols remain unchanged.
- Copy and content: unchanged apart from live scanner counts and elapsed times.

## Interaction checks

- `Other Web endpoints` expands without horizontal movement.
- CUA scrolled the inventory by one page and the content position changed.
- The 3 pt indicator appeared during that scroll and disappeared after the enforced 0.7 second inactivity timeout.
- The native scrollbar is disabled rather than merely asked to autohide, so system scrollbar preferences cannot reserve layout width.
- The footer stays fixed while the inventory scrolls.
- The same transient overlay implementation is attached to the service-detail scroll view.

## Comparison history

1. Earlier P1: build 17 configured AppKit's native scroller as overlay/autohide, but the user's actual menu-panel state still retained it and it continued to affect layout.
2. Intermediate P1: the first build 18 candidate disabled the native scroller but placed the custom indicator outside the visible GeometryReader bounds.
3. Fix: removed the native scroller entirely, observed clip-view bounds changes, placed a 3 pt custom indicator 4 pt inside the trailing edge, and forced it to fade after 0.7 seconds.
4. Post-fix evidence: the combined comparison visibly shows the thin indicator only in the middle scrolling state, no indicator in the right idle state, and no horizontal difference between the two build 18 layouts.

Focused-region comparison was not necessary because the 2× full-height captures make the entire right-edge behavior and row alignment directly readable.

final result: passed
