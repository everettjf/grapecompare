#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

entitlements="macos/GrapeCompare/GrapeCompare.entitlements"
project="macos/GrapeCompare.xcodeproj/project.pbxproj"
info="macos/GrapeCompare/Info.plist"

plutil -lint "$entitlements" "$info" >/dev/null

for key in \
    com.apple.security.app-sandbox \
    com.apple.security.files.bookmarks.app-scope \
    com.apple.security.files.user-selected.read-write; do
    escaped_key="${key//./\\.}"
    test "$(plutil -extract "$escaped_key" raw "$entitlements")" = "true"
done

test "$(rg -c 'ENABLE_APP_SANDBOX = YES;' "$project")" -eq 2
test "$(rg -c 'ENABLE_USER_SELECTED_FILES = readwrite;' "$project")" -eq 2
test "$(rg -c 'CODE_SIGN_ENTITLEMENTS = GrapeCompare/GrapeCompare.entitlements;' "$project")" -eq 2
! rg -n 'ENABLE_APP_SANDBOX = NO|com\.apple\.security\.network\.(client|server)' \
    "$project" "$entitlements"
! plutil -extract CFBundleURLTypes raw "$info" >/dev/null 2>&1

for removed in \
    macos/CLI \
    macos/GrapeCompare/Core/GitRepository.swift \
    macos/GrapeCompare/Core/GitRepositoryWorkspace.swift \
    macos/GrapeCompare/Core/ExternalMergeProtocol.swift \
    macos/GrapeCompare/Views/GitCompareView.swift \
    scripts/build-release.sh \
    scripts/validate-release.sh \
    Casks/grapecompare.rb; do
    test ! -e "$removed"
done

! rg -n '/usr/bin/git|Process\(|--merge|grapecompare://|difftool|mergetool' \
    macos/GrapeCompare --glob '*.swift' --glob '*.plist'
rg -q 'bookmarkData' macos/GrapeCompare/CompareFilesIntent.swift
rg -q 'resolvingBookmarkData' macos/GrapeCompare/AppState.swift
! rg -n 'quickActionPaths|pendingCompareFilesIntentPaths' macos/GrapeCompare

echo "Validated Mac App Store-only sandbox configuration."
