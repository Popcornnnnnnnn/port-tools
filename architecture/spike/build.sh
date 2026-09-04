#!/bin/sh
set -eu

script_root="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
repository_root="$(CDPATH= cd -- "$script_root/../.." && pwd)"
build_root="$repository_root/architecture/.build"
app="$build_root/Port Tools Architecture.app"
go_binary="${GO_BIN:-}"

if [ -z "$go_binary" ] || [ ! -x "$go_binary" ]; then
    echo "Set GO_BIN to an explicit Go compiler path." >&2
    exit 2
fi

rm -rf "$build_root"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"

"$go_binary" build \
    -trimpath \
    -ldflags "-s -w" \
    -o "$app/Contents/Helpers/port-tools-core" \
    "$script_root/core/main.go"

xcrun swiftc \
    -parse-as-library \
    -target arm64-apple-macosx14.0 \
    "$script_root/app/PortToolsArchitectureApp.swift" \
    -o "$app/Contents/MacOS/PortToolsArchitecture"

cp "$script_root/Info.plist" "$app/Contents/Info.plist"
codesign --force --sign - --options runtime "$app/Contents/Helpers/port-tools-core"
codesign --force --sign - --options runtime "$app"

echo "$app"
