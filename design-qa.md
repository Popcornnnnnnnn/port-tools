# Design QA — build 20 stable disclosure layout

## Evidence

- Source visual truth: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-d22c95bb-7607-44fc-bda6-d9137e482d2b.png`
- Build 19 collapse sequence: `/tmp/port-tools-jump.HTN4r9/frame-129.png` through `frame-135.png`
- Build 20 collapsed frame: `/tmp/port-tools-build20.yKoVMx/frame-054.png`
- Build 20 expanded frame: `/tmp/port-tools-build20.yKoVMx/frame-055.png`
- Build 20 settled-chevron frame: `/tmp/port-tools-build20.yKoVMx/frame-056.png`
- State: `Other Web endpoints` expanded in the light appearance.

## Normalization

- Source: 832 × 1276 px at 2× density, representing approximately a 416 × 638 pt menu panel.
- Implementation captures: 956 × 1480 px including the native preview-window shadow at 2× density.
- Compared implementation crops: 820 × 1282 px, representing the 410 × 641 pt app content area.
- CSS size/device scale factor: not applicable; this is a native SwiftUI/AppKit application.
- The comparison removes the preview title bar and outer shadow. Live endpoint counts and ages changed during the test and are not visual regressions.

## Findings

- No actionable P0/P1/P2 findings remain in build 20.
- The supplied/build 17 state shows a persistent dark native scrollbar and a reserved right gutter.
- Build 18 removes the native scroller from the accessibility hierarchy and layout. A 3 pt translucent custom indicator overlays the right edge during a real scroll gesture, then is absent in the one-second idle capture.
- Build 19 also removes the old 8 pt trailing inset from expanded secondary rows and hides native indicators at SwiftUI creation time. Right-side metadata now uses the same content boundary whether the list is collapsed, expanded, scrolling, or idle.
- User testing found that build 19 still jumped while toggling `Other`. Frame-sequence inspection showed that the remaining motion came from animated disclosure geometry, while layout-driven clip-view notifications also incorrectly counted as scroll activity.
- Build 20 fixes the content document at 410 pt, performs the secondary content insertion without geometry animation, animates only the chevron, and reveals the custom indicator only when the actual scroll offset changes.

## Required fidelity surfaces

- Fonts and typography: unchanged from the accepted interface; hierarchy, weights, truncation, and monospaced endpoint text remain stable.
- Spacing and layout rhythm: no scrollbar gutter exists; the left child hierarchy indent remains while the previous compensating right inset is removed.
- Colors and visual tokens: the active indicator uses secondary foreground at 28% opacity and has no track; the idle state contains no scrollbar pixels.
- Image quality and asset fidelity: no raster or custom product assets are involved; existing SF Symbols remain unchanged.
- Copy and content: unchanged apart from live scanner counts and elapsed times.

## Interaction checks

- `Other Web endpoints` expands in one layout frame; the following changed frame is limited to the chevron rotation.
- Pixel differences above the `Other Web endpoints` row are empty between collapsed and expanded frames, confirming that existing project rows and their trailing controls do not move.
- CUA scrolled the inventory by one page and the content position changed.
- The 3 pt indicator appeared during that scroll and disappeared after the enforced 0.7 second inactivity timeout.
- The native scrollbar is disabled rather than merely asked to autohide, so system scrollbar preferences cannot reserve layout width.
- The footer stays fixed while the inventory scrolls.
- The same transient overlay implementation is attached to the service-detail scroll view.
- After repeated disclosure and scroll interactions, the preview process remained idle at 0.0% CPU; no layout-update loop remained.

## Comparison history

1. Earlier P1: build 17 configured AppKit's native scroller as overlay/autohide, but the user's actual menu-panel state still retained it and it continued to affect layout.
2. Intermediate P1: the first build 18 candidate disabled the native scroller but placed the custom indicator outside the visible GeometryReader bounds.
3. Fix: removed the native scroller entirely, observed clip-view bounds changes, placed a 3 pt custom indicator 4 pt inside the trailing edge, and forced it to fade after 0.7 seconds.
4. User follow-up P2: although the indicator was hidden, the expanded `Other` rows still retained an unrelated 8 pt trailing inset, making their metadata look squeezed left.
5. Fix: applied `.scrollIndicators(.hidden)` and zero trailing scroll-content margin at the SwiftUI layer, then removed the nested list's explicit trailing inset. An attempted AppKit inset reset was rejected during QA because it caused a 99.6% CPU update loop; it is not present in the final build.
6. User follow-up: build 19 still felt as though it jumped. A 300-frame capture showed two consecutive large layout-change frames during collapse; this invalidated the earlier settled-state-only acceptance.
7. Fix: removed animated geometry from global secondary disclosures, isolated animation to the chevron, ignored bounds notifications when the scroll offset is unchanged, and fixed the inventory document width.
8. Post-fix evidence: build 20 changes the disclosure content in one frame and then only the chevron pixels. No pixels above the disclosure row change, so existing rows are not horizontally or vertically displaced.

Focused-region comparison was not necessary because the 2× full-height captures make the entire right-edge behavior and row alignment directly readable.

final result: passed
