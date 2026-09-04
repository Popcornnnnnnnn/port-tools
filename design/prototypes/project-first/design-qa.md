# Design QA — Live project-first + search prototype

Date: 2026-09-04
final result: passed

## Comparison target

- Source visual truth: `/Users/forge/Workspace/port-tools/design/prototypes/comparison/source-direction1.jpg` and `/Users/forge/Workspace/port-tools/design/prototypes/search-first/implementation-main.jpg`
- Implementation: `http://127.0.0.1:45123/`
- Combined comparison view: `http://127.0.0.1:45123/?qa=1`
- Browser-rendered implementation screenshot: `/Users/forge/Workspace/port-tools/design/prototypes/project-first/implementation-live.png`
- Combined comparison screenshot: `/Users/forge/Workspace/port-tools/design/prototypes/project-first/qa-live-comparison.png`
- Source pixels: 608 × 901 for each selected direction capture
- Implementation and comparison captures: 1280 × 720 at device scale 1
- Intended component size: 410 px wide, up to 720 px high
- State: light appearance; real local scan loaded; project groups partly expanded; search tested both closed and open

## Full-view comparison evidence

The combined browser capture places both selected source directions beside the live implementation. The implementation retains Direction 1's quiet macOS panel, project-first hierarchy, compact rows, explicit healthy/warning states, and subordinate branch/port metadata. Direction 3 contributes the focused search field, but it stays hidden until the header search control or Command-K is used.

The selected sources used simulated data, while the implementation intentionally uses the scanner's live project, application, Web classification, Git branch, GitHub remote, listener, and process evidence. That content difference is expected and is the purpose of this trial build. No actionable P0, P1, or P2 visual mismatch remains.

## Focused-region evidence

- Project disclosure: the repeated right-side arrow column is gone. Each project has one small leading disclosure indicator, the entire header row toggles expansion, and the right side contains only a service/attention summary.
- Project hierarchy: a Git worktree is the top-level card; multiple application manifests appear as compact subheadings; service rows remain the actionable leaves. Single-application projects omit the redundant middle heading.
- Search: the header control and Command-K reveal the Direction 3 search field. A `19201` query reduced the inventory to the matching Boonray project and `mine-cloud-proxy` service, with the project temporarily expanded.
- Runtime naming: an untitled Node service is displayed as `mine-cloud-proxy`, derived from its script path; the generic runtime name `node` remains only in evidence.
- Service detail: selecting a service revealed Open, Copy, Name, Stop, Web evidence, and project-path controls without turning every row into a permanent toolbar.

## Required fidelity surfaces

- Fonts and typography: system UI and monospace fallbacks preserve the native macOS character. Project names remain strongest, service names are secondary, and branch, remote, address, and age truncate without displacing status.
- Spacing and layout rhythm: 51 px project headers and 49 px service rows preserve the compact source rhythm. Insets and one thin rule communicate nesting without card clutter.
- Colors and visual tokens: neutral white/gray surfaces match both sources. Green is reserved for verified Web state; amber identifies LAN exposure, suspected Web endpoints, or project attention; red appears only inside the stop preview.
- Image quality and asset fidelity: the product has no imagery. All interface icons use the existing Phosphor family; no placeholder art, handcrafted SVG, emoji, or CSS-drawn icons were introduced.
- Copy and content: labels describe project, application, listener, and evidence in plain language. `LIVE` distinguishes real inventory from earlier demos. Naming and stopping explicitly state that they remain trial simulations.
- Accessibility: icon-only controls have accessible names, project and service rows are keyboard focusable, disclosure state is announced, focus styling is visible, reduced motion is supported, and all status colors include text labels.
- Responsiveness: the panel fits the 410 × 720 target and becomes viewport-width on narrow windows; inventory remains independently scrollable.

## Primary interactions tested

- Live `/api/inventory` response loaded and updated the visible project and service counts.
- Project header row collapsed and persisted its state.
- Search opened from the header, accepted a port query, filtered project/app/service content, and automatically expanded the match.
- A service row expanded its action and evidence controls.
- The Web evidence modal displayed real project, application, command, HTTP, framework, and bind-scope evidence and closed normally.
- No Vite error overlay, broken asset, failed inventory state, or uncaught error was visible during the interaction pass. The CUA browser surface does not expose a separate console-log API.

## Comparison history

1. Initial live comparison showed a broken project-first source image because the QA route referenced a non-existent capture (P1 comparison evidence).
2. Fix: changed the source to the verified Direction 1 capture used by the three-direction comparison page.
3. Post-fix comparison displayed both 608 × 901 source captures and the live implementation together; the broken image was gone.
4. Initial runtime content labeled an untitled command-path service as `node` (P2 information hierarchy).
5. Fix: derive the display/application fallback from the executable script basename while retaining the raw runtime name in evidence.
6. Post-fix browser snapshot displayed `mine-cloud-proxy` at both the application and service levels, eliminating runtime-name leakage from the primary inventory.

## Follow-up polish

- P3: Native SwiftUI should validate the exact material blur, shadow, hover behavior, VoiceOver order, and Dynamic Type sizing on supported macOS versions.
- P3: GitHub remotes currently display as compact text; a later native detail view can make them directly openable without adding noise to the default inventory.
