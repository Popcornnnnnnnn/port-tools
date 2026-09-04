# Design QA — Direction 2: Attention-first triage

## Evidence

- Source visual truth: `/Users/forge/Workspace/port-tools/design/references/direction-2-attention-first.png` (`941 × 1671` px).
- Normalized source crop: `/Users/forge/Workspace/port-tools/design/prototypes/attention-first/qa-source-cropped.png` (`835 × 1516` px), cropped to the popover border and rendered into a `394 × 700` CSS slot.
- Browser-rendered implementation: `/Users/forge/Workspace/port-tools/design/prototypes/attention-first/implementation-main.jpg` (`608 × 901` px browser capture).
- Focused interaction evidence: `/Users/forge/Workspace/port-tools/design/prototypes/attention-first/implementation-review-lan.jpg` (`608 × 901` px browser capture).
- Combined comparison: `/Users/forge/Workspace/port-tools/design/prototypes/attention-first/qa-comparison.jpg` (`608 × 901` px browser capture).
- Intended component viewport: `394 × 700` CSS px, light theme, default five-service state.
- Density normalization: source popover was cropped from the generated raster and both source and implementation were rendered in equal `394 × 700` CSS slots; the combined browser view scales both slots to `68%` only to fit the available in-app browser width.

## Findings

No actionable P0, P1, or P2 visual differences remain.

- Fonts and typography: both views use the native macOS sans-serif hierarchy, compact uppercase section labels, semibold service names, and subdued secondary metadata. Small optical-weight differences from raster generation are acceptable.
- Spacing and layout rhythm: header, attention section, healthy list, blank breathing room, footer, corner radius, and shadow align at the same component size. The implementation keeps slightly stronger row separators for click affordance; this is acceptable.
- Colors and visual tokens: warm amber attention surface, amber and green semantic states, neutral background, and subtle borders match the target. No gradient or decorative styling was added to the menu surface.
- Image quality and asset fidelity: the menu itself contains no photographic or branded assets. Runtime icons use Phosphor rather than handcrafted SVG or text glyphs. The generated raster remains a reference artifact only.
- Copy and content: service names, aliases, ports, ages, status copy, and footer action match the selected target. `DEMO` is an intentional addition so fixed sample data cannot be mistaken for a live scan.

## Focused Region Comparison

The attention-review modal was captured separately because it is not depicted in the source mock. It preserves the same typography, semantic amber color, radius, border, and density while making bind scope and LAN reachability explicit. No additional crop was needed because all modal text and controls are readable in the full browser capture.

## Comparison History

### Iteration 1 — blocked

- P2: the combined comparison included the generated image's outer backdrop instead of matching the popover border, creating false scale and proportion differences.
- P2: implementation metadata ordered project before address, while the target ordered address before project for healthy services.
- P2: status-pill icons widened attention rows and forced wrapping that did not appear in the target.
- Fixes: created a border-aligned source crop, normalized both views into equal component slots, matched metadata ordering and wrapping, removed pill icons, and restored outlined header icon buttons.

### Iteration 2 — passed

- Post-fix combined evidence: `qa-comparison.jpg` shows aligned information hierarchy, section proportions, semantic colors, copy, footer position, and row density.
- Residual P3: implementation separators and body text are marginally crisper than the generated raster. This improves real UI legibility and does not change the design direction.

## Primary Interactions Tested

- Refreshed the scan and verified the service-count feedback.
- Opened the `LAN exposed` review, verified bind-scope evidence, and entered safe-stop review.
- Opened a healthy app inspector and its Web-classification evidence.
- Opened the naming flow, verified the unique default `scanner-fixtures`, saved `scanner-fixtures.localhost:4111`, and observed the row update.
- Completed simulated graceful stop for `stationControl`; verified it disappeared and the count changed from five to four; reload restored fixture data.
- Checked browser console warnings and errors: none.

## Implementation Checklist

- [x] Same-size source/implementation comparison.
- [x] Attention-first hierarchy with no disclosure arrows.
- [x] Positive `Web verified` reminders remain visible.
- [x] Core review, detail, evidence, naming, and safe-stop flows work.
- [x] Mock actions are clearly labeled and cannot touch real processes.
- [x] Browser console is clean.

final result: passed
