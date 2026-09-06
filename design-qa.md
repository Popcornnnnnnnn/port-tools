# Design QA — build 22 standalone apps and native motion

## Evidence

- Accepted visual baseline: `/tmp/port-tools-build21-collapsed.png`
- Build 22 collapsed inventory: `/tmp/port-tools-build22.y33nJb/03-collapsed.png`
- Build 22 expanded `Other Web endpoints`: `/tmp/port-tools-build22.y33nJb/02-other-expanded.png`
- Build 22 service detail: `/tmp/port-tools-build22.y33nJb/04-detail.png`
- Side-by-side comparison: `/tmp/port-tools-build22.y33nJb/05-main-comparison.png`
- Interaction references: `https://reactbits.dev/animations/animated-content`, `https://reactbits.dev/components/animated-list`, `https://reactbits.dev/animations/fade-content`
- State: light appearance, 382 pt menu panel, live scanner data.

## Normalization

- Baseline and implementation captures use the same 382 × 672 pt content area at 2× density.
- CSS size and device scale factor are not applicable; this is a native SwiftUI/AppKit application.
- Live endpoint counts, titles, branches, and elapsed times are dynamic content, not visual regressions.

## Findings

- No actionable P0, P1, or P2 findings remain in build 22.
- P3: the standalone TokenTracker title truncates in the inventory at the current compact width. Its full title remains available in Service details, so this is acceptable for the menu-bar density target.
- The accepted build 21 typography, row widths, control alignment, colors, and spacing tokens remain unchanged.
- The additional TokenTracker row is intentional: a non-Git service is now promoted only when it is a confirmed HTTP 2xx HTML page with a nonempty title.

## Required fidelity surfaces

- Fonts and typography: unchanged; primary titles, repository context, monospaced endpoints, ages, and secondary metadata retain the established hierarchy.
- Spacing and layout rhythm: the 382 pt width and existing insets remain fixed through collapsed, expanded, and detail states.
- Colors and visual tokens: disclosure motion adds no new persistent color or decorative chrome.
- Assets: existing SF Symbols remain; no raster assets or web UI are embedded.
- Copy and content: standalone apps do not receive a fabricated Git branch or project rename action.

## Interaction checks

- `Other Web endpoints` and `Other listeners` use a 0.20 s low-bounce reveal with opacity, a 5 pt directional offset, and a subtle 0.985 vertical scale.
- Disclosure content keeps a fixed width and animates only height and presentation, so the right-side alignment does not jump or reserve scrollbar space.
- Reduce Motion replaces spring movement with a short fade.
- Service details enter from the right with a short low-bounce transition and return to the unchanged underlying inventory state.
- Back has a 28 pt hit target, hover fill, pressed opacity/scale feedback, `Esc`, and `Command-[` support.
- CUA verified opening an Other service, returning with Back, and preserving the expanded Other section.
- TokenTracker appears in the primary inventory while redirects, HTTP errors, APIs, and unconfirmed listeners remain in their secondary groups.
- Search, fixed footer, custom transient scroll indicator, and local-route behavior remain intact.

## Comparison history

1. Build 21 established the accepted compact 382 pt panel and stable overlay scrollbar behavior.
2. React Bits references were used for timing and direction principles only; Magnet, Click Spark, glare, and cursor-trail effects were rejected as too noisy for a menu-bar utility.
3. Build 22 adds restrained native motion and promotes high-confidence standalone HTML applications without changing the accepted visual system.
4. The before/after comparison confirms that existing rows keep their horizontal geometry; only the newly promoted application changes vertical content length.

final result: passed
