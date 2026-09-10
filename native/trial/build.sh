#!/bin/sh
set -eu

script_root="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
repository_root="$(CDPATH= cd -- "$script_root/../.." && pwd)"
build_root="$repository_root/native/.build"
app="$build_root/Port Tools.app"
go_binary="${GO_BIN:-$(command -v go || true)}"
version="$(tr -d '[:space:]' < "$repository_root/VERSION")"
build_arch="${PORT_TOOLS_ARCH:-$(uname -m)}"

case "$build_arch" in
    arm64)
        go_arch="arm64"
        swift_target="arm64-apple-macosx14.0"
        ;;
    x86_64|amd64)
        go_arch="amd64"
        swift_target="x86_64-apple-macosx14.0"
        ;;
    *)
        echo "Unsupported build architecture: $build_arch" >&2
        exit 2
        ;;
esac

if [ -z "$go_binary" ] || [ ! -x "$go_binary" ]; then
    echo "Set GO_BIN to an explicit Go compiler path." >&2
    exit 2
fi

rm -rf "$build_root"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
mkdir -p "$app/Contents/Library/LaunchDaemons" "$app/Contents/Library/LaunchServices"

(
    cd "$repository_root/core"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$go_arch" "$go_binary" build \
        -trimpath \
        -ldflags "-s -w -X main.version=$version" \
        -o "$app/Contents/Helpers/port-tools-core" \
        .
)

(
    cd "$repository_root/portless-helper"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$go_arch" "$go_binary" build \
        -trimpath \
        -ldflags "-s -w -X main.version=$version" \
        -o "$app/Contents/Library/LaunchServices/port-tools-portless-helper" \
        .
)

xcrun swiftc \
    -parse-as-library \
    -O \
    -target "$swift_target" \
    "$repository_root/native/PortTools/Models.swift" \
    "$repository_root/native/PortTools/Localization.swift" \
    "$repository_root/native/PortTools/PortlessService.swift" \
    "$repository_root/native/PortTools/CoreClient.swift" \
    "$repository_root/native/PortTools/InventoryStore.swift" \
    "$repository_root/native/PortTools/InventoryUI.swift" \
    "$repository_root/native/PortTools/Settings.swift" \
    "$repository_root/native/PortTools/Updates.swift" \
    "$repository_root/native/PortTools/AppLifecycle.swift" \
    -o "$app/Contents/MacOS/PortTools"

cp "$script_root/Info.plist" "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "28" "$app/Contents/Info.plist"
cp "$script_root/Resources/PortTools.icns" "$app/Contents/Resources/PortTools.icns"
cp -R "$repository_root/native/Localization/zh-Hans.lproj" "$app/Contents/Resources/"
cp "$repository_root/native/PortlessHelper.plist" "$app/Contents/Library/LaunchDaemons/PortlessHelper.plist"
chmod 755 "$app/Contents/MacOS/PortTools"
chmod 755 "$app/Contents/Helpers/port-tools-core"
chmod 755 "$app/Contents/Library/LaunchServices/port-tools-portless-helper"
codesign --force --sign - --options runtime "$app/Contents/Helpers/port-tools-core"
codesign --force --sign - --options runtime "$app/Contents/Library/LaunchServices/port-tools-portless-helper"
codesign --force --sign - --options runtime "$app"

echo "$app"
