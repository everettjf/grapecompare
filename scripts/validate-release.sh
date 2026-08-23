#!/bin/bash
set -euo pipefail

raw_version="${1:-}"
version="${raw_version#v}"
release_dir="${2:-}"
project_root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "$version" || -z "$release_dir" ]]; then
  echo "usage: $0 <version> <release-directory>" >&2
  exit 64
fi

archive="$release_dir/GrapeCompare-$version.zip"
checksum="$archive.sha256"
staged_app="$release_dir/.staging/GrapeCompare.app"
validation_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/grapecompare-validation.XXXXXX")"
trap 'rm -rf "$validation_dir"' EXIT

test -f "$archive"
test -f "$checksum"
(cd "$release_dir" && shasum -a 256 -c "$(basename "$checksum")")
ditto -x -k "$archive" "$validation_dir"
expanded_app="$validation_dir/GrapeCompare.app"
test -d "$expanded_app"
test -d "$staged_app"

for app in "$staged_app" "$expanded_app"; do
  executable="$app/Contents/MacOS/GrapeCompare"
  test -x "$executable"
  lipo -verify_arch arm64 "$executable"
  lipo -verify_arch x86_64 "$executable"
  minimum_version="$(vtool -show-build "$executable" | awk '/minos/{print $2; exit}')"
  test "$minimum_version" = "14.0"
  test "$(defaults read "$app/Contents/Info" CFBundleShortVersionString)" = "$version"
  test "$(defaults read "$app/Contents/Info" LSMinimumSystemVersion)" = "14.0"
  codesign --verify --deep --strict --verbose=2 "$app"
  if codesign --display --entitlements :- "$app" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
    echo "direct-distribution artifact unexpectedly contains App Sandbox" >&2
    exit 65
  fi
  test "$(defaults read "$app/Contents/Info" CFBundleDevelopmentRegion)" = "en"
  test -f "$app/Contents/Resources/zh-Hans.lproj/Localizable.strings"
  ruby "$project_root/macos/Tests/validate-app-intent.rb" "$app"
done

echo "Validated GrapeCompare $version universal release archive (macOS 14+, unsandboxed, checksummed)."
