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
export_path="$dist_root/export"
export_options="$repository_root/scripts/ExportOptions.plist"
app_path="$export_path/Port Tools.app"
dmg_path="$dist_root/Port-Tools-$release_version.dmg"
volume_name="Port Tools $release_version"
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
"$repository_root/scripts/normalize-xcode-project.sh" "$native_root/PortTools.xcodeproj/project.pbxproj"
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

rm -rf "$export_path"
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options"

codesign --force --options runtime --timestamp \
  --preserve-metadata=identifier,entitlements \
  --sign "$developer_identity" \
  "$app_path/Contents/Helpers/port-tools-core"
codesign --force --options runtime --timestamp \
  --preserve-metadata=identifier,entitlements \
  --sign "$developer_identity" \
  "$app_path"

lipo "$app_path/Contents/MacOS/PortTools" -verify_arch arm64
lipo "$app_path/Contents/Helpers/port-tools-core" -verify_arch arm64
[[ -f "$app_path/Contents/Resources/PortTools.icns" ]]
[[ -d "$app_path/Contents/Resources/zh-Hans.lproj" ]]
codesign --verify --deep --strict --verbose=2 "$app_path"
helper_signature="$(codesign -dv --verbose=4 "$app_path/Contents/Helpers/port-tools-core" 2>&1)"
grep -q 'flags=.*runtime' <<<"$helper_signature"

staging="$dist_root/dmg-root"
rw_dmg="$dist_root/Port-Tools-$release_version-rw.dmg"
mountpoint="$dist_root/dmg-mount"
rm -rf "$staging" "$mountpoint"
rm -f "$rw_dmg" "$dmg_path"
mkdir -p "$staging/.background"
cp -R "$app_path" "$staging/Port Tools.app"
ln -s /Applications "$staging/Applications"
cp "$repository_root/design/marketing/dmg-background@2x.png" "$staging/.background/background.png"
[[ "$(sips -g pixelWidth "$staging/.background/background.png" | awk '/pixelWidth/ {print $2}')" == "1200" ]]
[[ "$(sips -g pixelHeight "$staging/.background/background.png" | awk '/pixelHeight/ {print $2}')" == "800" ]]
hdiutil create -volname "$volume_name" -srcfolder "$staging" -ov -format UDRW "$rw_dmg" >/dev/null
mkdir -p "$mountpoint"
hdiutil attach "$rw_dmg" -readwrite -noverify -noautoopen -mountpoint "$mountpoint" >/dev/null
trap 'hdiutil detach "$mountpoint" >/dev/null 2>&1 || true' EXIT
osascript - "$mountpoint" <<'APPLESCRIPT'
on run argv
  set mountPath to item 1 of argv
  set targetFolder to POSIX file mountPath as alias
  tell application "Finder"
    open targetFolder
    set current view of container window of targetFolder to icon view
    set toolbar visible of container window of targetFolder to false
    set statusbar visible of container window of targetFolder to false
    set pathbar visible of container window of targetFolder to false
    set bounds of container window of targetFolder to {100, 100, 700, 500}
    set viewOptions to icon view options of container window of targetFolder
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:background.png" of targetFolder
    set position of item "Port Tools.app" of targetFolder to {170, 210}
    set position of item "Applications" of targetFolder to {430, 210}
    update targetFolder without registering applications
    delay 2
    close container window of targetFolder
    delay 1
  end tell
end run
APPLESCRIPT
[[ -f "$mountpoint/.DS_Store" ]] || { echo "Finder did not persist the DMG layout." >&2; exit 1; }
sync
sleep 2
hdiutil detach "$mountpoint" >/dev/null
trap - EXIT
hdiutil convert "$rw_dmg" -format UDZO -o "$dmg_path" >/dev/null
rm -f "$rw_dmg"
codesign --force --timestamp --sign "$developer_identity" "$dmg_path"
notary_result="$dist_root/notary-result.json"
xcrun notarytool submit "$dmg_path" \
  --keychain-profile "$notary_profile" \
  --wait \
  --output-format json | tee "$notary_result"
notary_status="$(plutil -extract status raw "$notary_result")"
if [[ "$notary_status" != "Accepted" ]]; then
  notary_id="$(plutil -extract id raw "$notary_result")"
  xcrun notarytool log "$notary_id" --keychain-profile "$notary_profile" >&2 || true
  exit 1
fi
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature -v "$dmg_path"
(cd "$dist_root" && shasum -a 256 "$(basename "$dmg_path")" > "$(basename "$dmg_path").sha256")

git tag -a "v$release_version" -m "Port Tools $release_version"
git push origin "v$release_version"
if [[ "$release_version" == *-* ]]; then
  gh release create "v$release_version" "$dmg_path" "$dmg_path.sha256" \
    --title "Port Tools $release_version" \
    --notes-file "$repository_root/updates-site/release-notes/1.0.0.html" \
    --prerelease
else
  gh release create "v$release_version" "$dmg_path" "$dmg_path.sha256" \
    --title "Port Tools $release_version" \
    --notes-file "$repository_root/updates-site/release-notes/1.0.0.html"
fi

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
