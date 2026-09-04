#!/bin/sh
set -eu

script_root="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
repository_root="$(CDPATH= cd -- "$script_root/../.." && pwd)"
build_root="$repository_root/native/.build"
app="$build_root/Port Tools.app"

rm -rf "$build_root"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Scanner"

xcrun swiftc \
    -parse-as-library \
    -target arm64-apple-macosx14.0 \
    "$script_root/PortToolsApp.swift" \
    -o "$app/Contents/MacOS/PortTools"

cp "$script_root/Info.plist" "$app/Contents/Info.plist"
cp "$repository_root/prototype/port_tools.py" "$app/Contents/Resources/Scanner/port_tools.py"
chmod 755 "$app/Contents/MacOS/PortTools"
codesign --force --sign - --options runtime "$app"

echo "$app"
