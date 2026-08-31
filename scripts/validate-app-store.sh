#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

entitlements="macos/GrapeCompare/GrapeCompare.entitlements"
project="macos/GrapeCompare.xcodeproj/project.pbxproj"
info="macos/GrapeCompare/Info.plist"
privacy="macos/GrapeCompare/PrivacyInfo.xcprivacy"

plutil -lint "$entitlements" "$info" "$privacy" >/dev/null

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
test "$(plutil -extract NSPrivacyTracking raw "$privacy")" = "false"
test "$(plutil -extract NSPrivacyCollectedDataTypes raw "$privacy")" = "0"
test "$(plutil -extract NSPrivacyTrackingDomains raw "$privacy")" = "0"
test "$(plutil -extract NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPIType raw "$privacy")" = \
    "NSPrivacyAccessedAPICategoryUserDefaults"
test "$(plutil -extract NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPITypeReasons.0 raw "$privacy")" = \
    "CA92.1"
test "$(plutil -extract NSPrivacyAccessedAPITypes.1.NSPrivacyAccessedAPIType raw "$privacy")" = \
    "NSPrivacyAccessedAPICategoryFileTimestamp"
test "$(plutil -extract NSPrivacyAccessedAPITypes.1.NSPrivacyAccessedAPITypeReasons.0 raw "$privacy")" = \
    "3B52.1"
test "$(plutil -extract NSPrivacyAccessedAPITypes.1.NSPrivacyAccessedAPITypeReasons.1 raw "$privacy")" = \
    "C617.1"

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
! rg -n -i \
    'git repository|git comparison|git live|commit graph|worktrees|HEAD ↔ (INDEX|WORKTREE)|INDEX ↔ WORKTREE' \
    macos/GrapeCompare/Localizable.xcstrings
rg -q 'bookmarkData' macos/GrapeCompare/CompareFilesIntent.swift
rg -q 'startAccessingSecurityScopedResource' macos/GrapeCompare/CompareFilesIntent.swift
rg -q 'resolvingBookmarkData' macos/GrapeCompare/AppState.swift
rg -F -q 'application(_ sender: NSApplication, open urls: [URL])' \
    macos/GrapeCompare/GrapeCompareApp.swift
! rg -q 'openFiles filenames' macos/GrapeCompare/GrapeCompareApp.swift
! rg -n 'quickActionPaths|pendingCompareFilesIntentPaths' macos/GrapeCompare

echo "Validated Mac App Store-only sandbox configuration."
