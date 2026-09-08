# Releasing Port Tools

Public releases are built only on the maintainer's Apple Silicon Mac. GitHub
Actions performs unsigned tests and smoke builds; it does not hold Apple or
Sparkle private keys.

## One-time setup

1. Install a `Developer ID Application` certificate in the login keychain.
2. Store App Store Connect credentials with `xcrun notarytool store-credentials port-tools-notary`.
3. Run Sparkle 2.9.4 `generate_keys` once. Confirm `generate_keys -p` matches
   `SUPublicEDKey` in `native/trial/Info.plist`.
4. Create Cloudflare Pages project `port-tools-updates`, connect production to
   the `updates` branch with `/` as its output directory, then bind
   `updates.popcornnn.xyz`.

Never commit a certificate, App Store Connect password, notary credential, or
Sparkle private key.

## Release

From a clean `release/v1.0.0` branch:

```sh
scripts/release.sh 1.0.0-rc.1
scripts/release.sh 1.0.0
```

The command runs unit/race/vet/compatibility/proxy/force-stop tests, archives an
arm64 app, signs nested code, creates the DMG, notarizes and staples it, verifies
Gatekeeper, publishes the GitHub Release, generates the signed appcast, and
pushes the static update site to `updates`. The appcast moves only after the
GitHub asset is public.

Install the RC and complete a real Sparkle upgrade to final before accepting
`v1.0.0`.

Before tagging each public candidate, measure the release-shaped app for the
full idle window:

```sh
python3 evaluation/measure_release_metrics.py --duration 600
```
