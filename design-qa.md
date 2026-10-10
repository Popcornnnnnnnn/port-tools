# Design QA — build 28 dark inventory hierarchy refinement

## Evidence

- User-provided baseline: `design/reference-light-before.png`
- Expanded dark inventory: `design/native-build24-dark-expanded.png`
- Collapsed project inventory: `design/native-build24-dark-collapsed.png`
- Side-by-side comparison: `design/native-build24-dark-comparison.png`
- User-reported hover gap: `design/reference-build24-hover-gap.png`
- User-reported collapsed alignment: `design/reference-build24-spacing-alignment.png`
- Refined collapsed inventory: `design/native-build24-alignment-collapsed.png`
- Refined single-project hover: `design/native-build24-alignment-hover.png`
- Refinement comparison: `design/native-build24-alignment-comparison.png`
- User-reported hierarchy issue: `design/reference-build24-hierarchy.png`
- Build 25 expanded hierarchy: `design/native-build25-hierarchy-expanded.png`
- Build 25 collapsed hierarchy: `design/native-build25-hierarchy-collapsed.png`
- Build 25 hierarchy comparison: `design/native-build25-hierarchy-comparison.png`
- Build 27 full-title overlay: `design/native-build27-title-tooltip.png`
- State: default dark appearance, 382 × 672 pt preview window, live scanner data.

## Normalization

- Baseline and implementation show the same inventory task at the same native panel width.
- The comparison normalizes both captures to the same visual height; CSS and device scale factor are not applicable to this SwiftUI/AppKit application.
- Endpoint counts, titles, branches, and elapsed times are live data and may differ between captures.

## Findings and corrections

- Replaced the flat white inventory with a dark neutral base, restrained grouped surfaces, low-contrast borders, and clearer project hierarchy.
- Removed the pointer-following glow and all persistent gradient decoration.
- Dark is the initial appearance; the overflow menu retains explicit Dark, Light, and System options.
- The full multi-app project header is a disclosure target, including its blank horizontal area.
- The first collapsed capture exposed two defects: project metadata wrapped and the app-count badge compressed vertically. Metadata is now a single truncating line and the badge has fixed horizontal sizing.
- Hover feedback is neutral and low contrast instead of blue or indigo, so clicking does not leave a visually loud block.
- The final collapsed capture confirms that child applications disappear, the chevron closes, the project summary remains readable, and `2 apps` stays horizontal.
- Single-project hover now fills the project card to its outer boundary; the inset hover stroke and blue shadow were removed.
- Multi-project and single-project titles now share the same 13 pt semibold type and 10 pt leading inset. Their metadata also shares the same 9.5 pt size and left edge.
- The project disclosure chevron moved to the trailing edge, so disclosure state no longer changes title alignment.
- The global overflow glyph was replaced by a labeled and accessible `gearshape` settings menu. Per-service overflow menus remain contextual actions.
- Build 25 gives the application header its own higher-contrast chrome surface and additional vertical space, separating app identity from inventory content without a decorative gradient.
- Header, multi-project, single-project, and secondary-section labels now resolve onto a consistent 16 pt content grid.
- Multi-project headers use the same 13 pt semibold project typography and 9.5 pt metadata typography as single-project cards.
- The standalone green project dot was replaced by the same verified shield used elsewhere; the disclosure chevron remains on the trailing edge.
- Build 26's native SwiftUI `.help` did not surface reliably inside the menu-bar panel and was rejected after user verification.
- Build 27 renders long service names through an app-owned hover overlay tied to the already verified full-card hover state. The overlay shows the complete title without resizing the inventory row.
- Build 27's overlay trigger was rejected after user verification: the entire service card revealed it immediately, and its upward placement could collide with the application header.
- Build 28 measures the rendered title against its full text width. A full-name overlay is now available only when that title is actually truncated, the pointer remains on the title text itself, and the one-second dwell completes.
- The build 28 overlay expands in place from the title's leading edge instead of above the row, so the first inventory item cannot be hidden behind the application header.
- Runtime ages now share one non-wrapping label treatment, keeping values such as `20h 2m` and `18h 38m` horizontal and right-aligned.

## Interaction and accessibility checks

- Project disclosure uses the existing short native animation and respects Reduce Motion through the shared disclosure component.
- Search results force matching projects open so collapsed state cannot hide a match.
- Existing search, refresh, context menus, service details, safe-stop review, footer, and transient scrolling remain intact.
- The candidate app was clicked through at a blank point inside the project header and captured after the animation completed.

## Comparison history

1. Build 21 established the compact 382 pt menu panel and stable overlay scrollbar behavior.
2. Build 22 added restrained native disclosure motion and promoted high-confidence standalone HTML applications.
3. Build 24 introduced the dark grouped visual system, appearance switching, whole-header project disclosure, and safe-stop review.
4. Build 25 unifies the alignment grid, project typography, verification symbol, full-card hover, and application-header hierarchy.
5. Build 26 attempted native full-title hover help, but the menu-bar presentation did not display it reliably.
6. Build 27 replaces that attempt with an app-owned, visually captured full-title overlay.
7. Build 28 narrows disclosure to a measured, title-only, one-second hover and keeps the full-name overlay inside the row.

final result: automated contract passed; manual title-dwell acceptance remains for the installed app
