#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/release.sh 1.0.0" >&2
  exit 2
fi

release_version="$1"
repository_root="$(cd "$(dirname "$0")/.." && pwd)"
native_root="$repository_root/native"
dist_root="$repository_root/dist/$release_version"
archive_path="$dist_root/PortTools.xcarchive"
app_path="$archive_path/Products/Applications/Port Tools.app"
dmg_path="$dist_root/Port-Tools-$release_version.dmg"
notary_profile="port-tools-notary"
sparkle_root="$native_root/.build/ReleasePackages"
sparkle_bin="$sparkle_root/SourcePackages/artifacts/sparkle/Sparkle/bin"
public_key="$(plutil -extract SUPublicEDKey raw "$native_root/trial/Info.plist")"
base_version="${release_version%%-*}"
release_build="${PORT_TOOLS_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"

[[ "$release_build" =~ ^[0-9]+$ ]] || { echo "PORT_TOOLS_BUILD_NUMBER must contain digits only." >&2; exit 2; }

cd "$repository_root"
[[ "$(git branch --show-current)" == "release/v1.0.0" ]] || { echo "Release from release/v1.0.0." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit all changes before releasing." >&2; exit 1; }
[[ "$(tr -d '[:space:]' < VERSION)" == "$base_version" ]] || { echo "VERSION does not match $base_version." >&2; exit 1; }
git rev-parse "v$release_version" >/dev/null 2>&1 && { echo "Tag v$release_version already exists." >&2; exit 1; }
command -v gh >/dev/null
gh auth status >/dev/null
command -v xcodegen >/dev/null

developer_identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)"
[[ -n "$developer_identity" ]] || { echo "No Developer ID Application certificate in the user keychain." >&2; exit 1; }
xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null

xcodebuild -resolvePackageDependencies \
  -project "$native_root/PortTools.xcodeproj" \
  -scheme PortTools \
  -clonedSourcePackagesDirPath "$sparkle_root/SourcePackages" >/dev/null
[[ -x "$sparkle_bin/generate_keys" && -x "$sparkle_bin/generate_appcast" ]] || { echo "Sparkle tools are unavailable." >&2; exit 1; }
[[ "$($sparkle_bin/generate_keys -p)" == "$public_key" ]] || { echo "Sparkle keychain private key does not match Info.plist." >&2; exit 1; }

go -C core test ./...
go -C core test -race ./...
go -C core vet ./...
python3 -m unittest discover -s tests -p 'test_*.py'
native/trial/build.sh >/dev/null
python3 evaluation/fixtures/verify_proxy.py --engine go
python3 evaluation/fixtures/verify_force_stop.py

mkdir -p "$dist_root"
(cd "$native_root" && xcodegen generate --spec project.yml)
xcodebuild archive \
  -project "$native_root/PortTools.xcodeproj" \
  -scheme PortTools \
  -configuration Release \
  -archivePath "$archive_path" \
  -derivedDataPath "$native_root/.build/Release" \
  -clonedSourcePackagesDirPath "$sparkle_root/SourcePackages" \
  MARKETING_VERSION="$base_version" \
  CURRENT_PROJECT_VERSION="$release_build" \
  ARCHS=arm64 \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$developer_identity"

codesign --force --options runtime --timestamp --sign "$developer_identity" "$app_path/Contents/Helpers/port-tools-core"
codesign --force --options runtime --timestamp --sign "$developer_identity" "$app_path"
lipo "$app_path/Contents/MacOS/PortTools" -verify_arch arm64
lipo "$app_path/Contents/Helpers/port-tools-core" -verify_arch arm64
codesign --verify --deep --strict --verbose=2 "$app_path"

staging="$dist_root/dmg-root"
rw_dmg="$dist_root/Port-Tools-$release_version-rw.dmg"
mountpoint="$dist_root/dmg-mount"
rm -rf "$staging" "$mountpoint"
rm -f "$rw_dmg" "$dmg_path"
mkdir -p "$staging/.background"
cp -R "$app_path" "$staging/Port Tools.app"
ln -s /Applications "$staging/Applications"
sips -z 400 600 "$repository_root/design/marketing/interface-dark.png" --out "$staging/.background/background.png" >/dev/null
hdiutil create -volname "Port Tools" -srcfolder "$staging" -ov -format UDRW "$rw_dmg" >/dev/null
mkdir -p "$mountpoint"
hdiutil attach "$rw_dmg" -readwrite -noverify -noautoopen -mountpoint "$mountpoint" >/dev/null
trap 'hdiutil detach "$mountpoint" >/dev/null 2>&1 || true' EXIT
osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "Port Tools"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 700, 500}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Port Tools.app" of container window to {170, 210}
    set position of item "Applications" of container window to {430, 210}
    close
    update without registering applications
  end tell
end tell
APPLESCRIPT
sync
sleep 2
hdiutil detach "$mountpoint" >/dev/null
trap - EXIT
hdiutil convert "$rw_dmg" -format UDZO -o "$dmg_path" >/dev/null
rm -f "$rw_dmg"
codesign --force --timestamp --sign "$developer_identity" "$dmg_path"
xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature -v "$dmg_path"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"

git tag -a "v$release_version" -m "Port Tools $release_version"
git push origin "v$release_version"
release_flags=()
if [[ "$release_version" == *-* ]]; then
  release_flags+=(--prerelease)
fi
gh release create "v$release_version" "$dmg_path" "$dmg_path.sha256" \
  --title "Port Tools $release_version" \
  --notes-file "$repository_root/updates-site/release-notes/1.0.0.html" \
  "${release_flags[@]}"

appcast_assets="$dist_root/appcast-assets"
mkdir -p "$appcast_assets"
cp "$dmg_path" "$appcast_assets/"
"$sparkle_bin/generate_appcast" \
  --download-url-prefix "https://github.com/Popcornnnnnnnn/port-tools/releases/download/v$release_version/" \
  --link "https://updates.popcornnn.xyz/appcast.xml" \
  "$appcast_assets"
"$repository_root/scripts/publish-updates.sh" "$release_version" "$appcast_assets/appcast.xml"

echo "Released Port Tools $release_version"
echo "DMG: $dmg_path"
