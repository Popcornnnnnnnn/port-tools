# Design QA — build 21 compact horizontal density

## Evidence

- Source visual truth: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-d22c95bb-7607-44fc-bda6-d9137e482d2b.png`
- Build 19 collapse sequence: `/tmp/port-tools-jump.HTN4r9/frame-129.png` through `frame-135.png`
- Build 20 collapsed frame: `/tmp/port-tools-build20.yKoVMx/frame-054.png`
- Build 20 expanded frame: `/tmp/port-tools-build20.yKoVMx/frame-055.png`
- Build 20 settled-chevron frame: `/tmp/port-tools-build20.yKoVMx/frame-056.png`
- User density reference: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-c2ed12c5-446f-4736-b808-3e1340f95959.png`
- Build 21 collapsed frame: `/tmp/port-tools-build21-collapsed.png`
- State: collapsed inventory in the light appearance; expanded, detail, and search states were also inspected through CUA.

## Normalization

- User density reference: 858 × 1380 px, containing the 410 pt menu panel.
- Build 21 capture: 900 × 1480 px including the native preview-window shadow at 2× density.
- The build 21 content area is 764 px wide, representing the intended 382 pt panel.
- CSS size/device scale factor: not applicable; this is a native SwiftUI/AppKit application.
- The comparison removes the preview title bar and outer shadow. Live endpoint counts and ages changed during the test and are not visual regressions.

## Findings

- No actionable P0/P1/P2 findings remain in build 21.
- The supplied/build 17 state shows a persistent dark native scrollbar and a reserved right gutter.
- Build 18 removes the native scroller from the accessibility hierarchy and layout. A 3 pt translucent custom indicator overlays the right edge during a real scroll gesture, then is absent in the one-second idle capture.
- Build 19 also removes the old 8 pt trailing inset from expanded secondary rows and hides native indicators at SwiftUI creation time. Right-side metadata now uses the same content boundary whether the list is collapsed, expanded, scrolling, or idle.
- User testing found that build 19 still jumped while toggling `Other`. Frame-sequence inspection showed that the remaining motion came from animated disclosure geometry, while layout-driven clip-view notifications also incorrectly counted as scroll activity.
- Build 20 fixes the content document at 410 pt, performs the secondary content insertion without geometry animation, animates only the chevron, and reveals the custom indicator only when the actual scroll offset changes.
- The build 20 default state remained horizontally loose: short project content formed a left cluster while age and overflow controls sat in a distant trailing cluster.
- Build 21 reduces the panel and detail width to 382 pt, removes the redundant trailing inset around flattened single-page rows, narrows the global secondary-section trailing inset, and gives process ages a stable 36 pt alignment column.

## Required fidelity surfaces

- Fonts and typography: unchanged from the accepted interface; hierarchy, weights, truncation, and monospaced endpoint text remain stable.
- Spacing and layout rhythm: the 28 pt width reduction removes inactive horizontal space; left hierarchy indents remain, while primary and global secondary trailing controls sit closer to their content.
- Colors and visual tokens: the active indicator uses secondary foreground at 28% opacity and has no track; the idle state contains no scrollbar pixels.
- Image quality and asset fidelity: no raster or custom product assets are involved; existing SF Symbols remain unchanged.
- Copy and content: unchanged apart from live scanner counts and elapsed times.

## Interaction checks

- `Other Web endpoints` expands in one layout frame; the following changed frame is limited to the chevron rotation.
- Pixel differences above the `Other Web endpoints` row are empty between collapsed and expanded frames, confirming that existing project rows and their trailing controls do not move.
- All three repository-context rows remain legible at 382 pt; the longest context stays on one line and uses the existing truncation behavior.
- `Other Web endpoints` expands without clipping its trailing age or info controls.
- Service details remain readable; the long process command wraps instead of overflowing.
- Search mode retains a full-width input and does not collide with the header controls.
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
9. User follow-up: the 410 pt collapsed inventory still left too much inactive space between the project content and trailing controls.
10. Fix: reduced both inventory and detail width to 382 pt, tightened only trailing insets, and standardized the process-age column without adding more metadata.
11. Post-fix evidence: the default state is 28 pt narrower while repository context, URLs, search, expanded secondary rows, and service details remain usable.

Focused-region comparison was not necessary because the 2× full-height captures make the entire right-edge behavior and row alignment directly readable.

final result: passed
