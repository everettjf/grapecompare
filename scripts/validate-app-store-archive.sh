#!/bin/bash
set -euo pipefail

archive="${1:?usage: validate-app-store-archive.sh <archive.xcarchive>}"
app="$archive/Products/Applications/GrapeCompare.app"
entitlements="$(mktemp -t grapecompare-entitlements).txt"
trap 'rm -f "$entitlements"' EXIT

test -d "$app"
test "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" = "1.0.0"
test "$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")" = "35"
test "$(lipo -archs "$app/Contents/MacOS/GrapeCompare")" = "x86_64 arm64"
codesign -d --entitlements "$entitlements" "$app" 2>/dev/null

for key in \
    com.apple.security.app-sandbox \
    com.apple.security.files.bookmarks.app-scope \
    com.apple.security.files.user-selected.read-write; do
    rg -F -q "[Key] $key" "$entitlements"
done

! rg -F -q '[Key] com.apple.security.get-task-allow' "$entitlements"
test ! -d "$app/Contents/Library/LoginItems"
test ! -d "$app/Contents/Helpers"
test "$(find "$app/Contents/MacOS" -type f | wc -l | tr -d ' ')" -eq 1

ruby "$(dirname "$0")/../macos/Tests/validate-app-intent.rb" "$app"
echo "Validated universal Mac App Store archive: $archive"
