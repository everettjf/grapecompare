# GrapeCompare

GrapeCompare is a private, sandboxed macOS comparison app for files, folders,
images, structured data, and three-way merges. All comparison work happens on
the Mac; the app has no account, telemetry, network entitlement, or cloud upload.

## Installation

Requires **macOS 15 or later**, on Apple silicon or Intel. The supported
installation channel is the [**Mac App Store**](https://apps.apple.com/us/app/grapecompare/id6796778424?mt=12).
See the [product website](https://xnu.app/grapecompare/) for supported workflows. GitHub hosts
the source code, not a supported installer. Homebrew and historical GitHub
release downloads are not supported installation paths for the current app.

After installation, choose two files or folders in the app, or use Finder Open
With, drag and drop, or the Compare Files Shortcut. Access is limited to items
you select. Three-way merging takes manually selected base, left, and right
inputs; it does not connect to Git.

## Product scope

- Text comparison with line and character-level differences, navigation, filters,
  editable output, and unified patch export.
- Recursive folder comparison with reviewed, transactional copy, replace, move,
  recoverable delete, dry-run reports, and undo.
- Image comparison with side-by-side, overlay, heatmap, alignment, metadata, and
  pixel metrics.
- Semantic JSON, plist, XCStrings, and Xcode project comparison.
- Read-only inspection of app bundles, signatures, entitlements, provisioning
  profiles, Mach-O files, and asset catalogs without launching inspected code.
- User-selected three-way text and image merging.
- Finder Open With, drag and drop, recent comparisons, and a Compare Files Shortcut.

GrapeCompare intentionally does not include a command-line tool, Git subprocess
integration, difftool/mergetool hooks, arbitrary-path URL schemes, or a
non-sandboxed distribution build.

## Requirements and build

GrapeCompare requires macOS 15 or later. Open `macos/GrapeCompare.xcodeproj`,
select the `GrapeCompare` scheme, and build for My Mac. Both Debug and Release
enable App Sandbox with user-selected read/write access and app-scoped security
bookmarks.

```bash
bash macos/Tests/run-tests.sh
ruby macos/Tests/validate-localizations.rb
xcodebuild -project macos/GrapeCompare.xcodeproj -scheme GrapeCompare \
  -destination 'platform=macOS' -configuration Debug build
```

## Distribution

The only supported product distribution is the Mac App Store. Archive and upload
with Xcode using Apple Distribution signing and a Mac App Store provisioning
profile. Do not disable App Sandbox for any build.

See [SUPPORT.md](SUPPORT.md), [SECURITY.md](SECURITY.md), and
[CONTRIBUTING.md](CONTRIBUTING.md).
