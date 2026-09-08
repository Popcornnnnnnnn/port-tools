#!/bin/sh
set -eu

script_root="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
repository_root="$(CDPATH= cd -- "$script_root/../.." && pwd)"
build_root="$repository_root/native/.build"
app="$build_root/Port Tools.app"
go_binary="${GO_BIN:-$(command -v go || true)}"
version="$(tr -d '[:space:]' < "$repository_root/VERSION")"

if [ -z "$go_binary" ] || [ ! -x "$go_binary" ]; then
    echo "Set GO_BIN to an explicit Go compiler path." >&2
    exit 2
fi

rm -rf "$build_root"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"

(
    cd "$repository_root/core"
    "$go_binary" build \
        -trimpath \
        -ldflags "-s -w -X main.version=$version" \
        -o "$app/Contents/Helpers/port-tools-core" \
        .
)

xcrun swiftc \
    -parse-as-library \
    -target arm64-apple-macosx14.0 \
    "$script_root/PortToolsApp.swift" \
    -o "$app/Contents/MacOS/PortTools"

cp "$script_root/Info.plist" "$app/Contents/Info.plist"
cp "$script_root/Resources/PortTools.icns" "$app/Contents/Resources/PortTools.icns"
chmod 755 "$app/Contents/MacOS/PortTools"
chmod 755 "$app/Contents/Helpers/port-tools-core"
codesign --force --sign - --options runtime "$app/Contents/Helpers/port-tools-core"
codesign --force --sign - --options runtime "$app"

echo "$app"
