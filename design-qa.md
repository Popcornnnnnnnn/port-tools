# Port Tools disclosure interaction QA

- Source visual truth: `/var/folders/k5/bs66lgrn1rs3lm2n4gfcnh2r0000gn/T/codex-clipboard-71bd8824-292c-435a-8069-13bbe9525a09.png`
- Source dimensions: 860 x 966 px
- Implementation: `/Users/forge/Applications/Port Tools.app`, build 9
- Viewport: native 410 x 640 pt menu-bar window
- State requested: collapsed, hover, expanded
- Density normalization: not available; implementation capture is blocked

## Full-view comparison evidence

The source image was opened and reviewed. It shows permanently prominent,
bold disclosure chevrons and no visible row-hover affordance. Build 9 replaces
the three independent disclosure implementations with one shared native
component: 8-8.5 pt semibold chevrons, 14% resting opacity, 58% hover opacity,
34% expanded opacity, a 4-5.5% neutral hover fill, and a 150 ms ease-out state
transition.

The running `LSUIElement` menu-bar app could not be attached by the available
computer-use surface (`timeoutReached`), so a same-state implementation
screenshot could not be captured. Build verification is not substituted for
visual evidence.

## Focused region comparison evidence

Blocked for the same reason. The required focused regions are the project
disclosure, nested Related services disclosure, and Other endpoints disclosure
in resting, hover, and expanded states.

## Findings

- [P2] Visual interaction states are not capture-verified.
  - Location: project, Related services, and Other disclosure rows.
  - Evidence: source capture is available; implementation capture is missing.
  - Impact: opacity and motion compile successfully but cannot be judged against
    the live macOS rendering in this QA pass.
  - Fix: capture the open menu-bar window in resting, hover, and expanded states,
    then compare the three focused regions.

## Required fidelity surfaces

- Fonts and typography: existing system typography retained; unverified visually.
- Spacing and layout rhythm: existing insets and row heights retained; unverified visually.
- Colors and visual tokens: native secondary/accent colors retained; new opacity states unverified visually.
- Image quality and assets: no raster assets; SF Symbols remain native.
- Copy and content: unchanged.

## Comparison history

- Pass 1: source opened; build 9 compiled and installed; implementation capture
  blocked because the automation surface cannot attach to the status-only app.

final result: blocked
