# Mac App Store release

GrapeCompare supports one distribution channel: the Mac App Store. Debug,
Release, Archive, and uploaded products must keep App Sandbox enabled.

## Local verification

Run the complete product checks before archiving:

```bash
bash macos/Tests/run-tests.sh
ruby macos/Tests/validate-localizations.rb
bash macos/Tests/validate-app-icons.sh
bash scripts/validate-app-store.sh
ruby scripts/run-correctness-audit.rb /tmp/grapecompare-correctness-report.json
xcodebuild -project macos/GrapeCompare.xcodeproj -scheme GrapeCompare \
  -destination 'platform=macOS' -configuration Debug build
```

## Archive and validate

Sign in to the Apple developer account in Xcode and ensure that the App Store
Connect app and Mac App Store provisioning profile exist for
`com.xnu.compare`. Then create and inspect a universal archive:

```bash
xcodebuild -project macos/GrapeCompare.xcodeproj -scheme GrapeCompare \
  -destination 'generic/platform=macOS' -configuration Release \
  -archivePath /tmp/GrapeCompare.xcarchive archive
bash scripts/validate-app-store-archive.sh /tmp/GrapeCompare.xcarchive
```

The validator requires build 35 of version 1.1.0, both Apple silicon and Intel
architectures, App Sandbox, app-scoped bookmarks, user-selected read/write
access, no debug entitlement, no helper executable, and an exact-two-file App
Intent.

## Export and upload

Exporting requires the signed-in Xcode account and an eligible Mac App Store
distribution profile:

```bash
xcodebuild -exportArchive \
  -archivePath /tmp/GrapeCompare.xcarchive \
  -exportPath /tmp/GrapeCompare-AppStore \
  -exportOptionsPlist macos/AppStoreExportOptions.plist \
  -allowProvisioningUpdates
```

Upload the resulting package with Xcode Organizer or Transporter. In App Store
Connect, complete the privacy declaration, screenshots, description, support
URL, age rating, pricing, export-compliance answer, and review notes. Submit
only after processing reports no signing, sandbox, entitlement, or metadata
errors.
