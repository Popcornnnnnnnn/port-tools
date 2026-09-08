#!/bin/bash
set -euo pipefail

release_version="${1:?release version required}"
appcast_path="${2:?appcast path required}"
repository_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$appcast_path" != /* ]]; then
  appcast_path="$repository_root/$appcast_path"
fi
[[ -f "$appcast_path" ]] || { echo "Appcast not found: $appcast_path" >&2; exit 1; }
remote_url="$(git -C "$repository_root" remote get-url origin)"
temporary_root="$(mktemp -d -t port-tools-updates.XXXXXX)"
trap 'rm -rf "$temporary_root"' EXIT

git clone --quiet "$remote_url" "$temporary_root/site"
cd "$temporary_root/site"
if git show-ref --verify --quiet refs/remotes/origin/updates; then
  git checkout --quiet -B updates origin/updates
else
  git checkout --quiet --orphan updates
  git rm -rf --quiet .
fi
cp -R "$repository_root/updates-site/." .
cp "$appcast_path" appcast.xml
git add --all
git diff --cached --quiet && { echo "Update feed already current."; exit 0; }
git commit -m "Publish Port Tools $release_version update feed"
git push origin updates
