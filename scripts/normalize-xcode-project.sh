#!/bin/bash
set -euo pipefail

project_file="${1:?path to project.pbxproj required}"
[[ -f "$project_file" ]] || { echo "Project file not found: $project_file" >&2; exit 1; }

# XcodeGen 2.44.1 writes objectVersion 77 even when the requested Xcode version
# is 15.x. Port Tools uses no Xcode 16-only synchronized groups, so normalize
# the two format markers for the free macos-14 / Xcode 15.4 GitHub runner.
sed -i '' \
  -e 's/objectVersion = 77;/objectVersion = 60;/' \
  -e 's/preferredProjectObjectVersion = 77;/preferredProjectObjectVersion = 60;/' \
  "$project_file"

grep -q 'objectVersion = 60;' "$project_file"
