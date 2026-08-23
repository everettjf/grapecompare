# Feature-alignment acceptance record

This record defines the completed 1.0.x alignment milestones. It is intentionally behavior-based: a version is not considered complete merely because its version number changed.

## 1.0.1 — Reliability

- Security-scoped access is deduplicated and released when a workspace closes.
- Active comparison, history, and filesystem-watch work is cancelled before teardown.
- Core, CLI, Git, permission, and release-path regressions pass.

## 1.0.2 — Git review and merge

- Changesets support durable local notes and reviewed-file progress.
- File history supports previous-revision comparison and explicit A/B selection.
- Three-way merge reports resolution progress and blocks output containing conflict markers.

## 1.0.3 — Images, folders, and macOS integration

- Image comparison includes Two-Up, One-Up, Split, Blink, Difference, Fit, Actual Pixels, synchronized pan/zoom, pixel inspection, channels, thresholds, and alignment.
- Folder comparison includes tree filtering, metadata, persistent custom/developer ignore profiles, dry-run synchronization plans, validated operations, and persistent undo.
- macOS integration includes CLI, App Intent/Finder Quick Action, Open With for exactly two items, and `grapecompare://compare` deep links.

## 1.0.4 — Polish and performance

- Full-resolution image recomputation is asynchronous, cancellable, and debounced rather than running during SwiftUI rendering.
- Image zoom exposes standard keyboard shortcuts and accessibility values; blink respects Reduce Motion.
- Release benchmarks cover large text, 1,024×1,024 RGBA images, 10,000-file folders, synchronization planning, and peak memory.

## Verification baseline

Run before publishing any build:

```bash
bash macos/Tests/run-tests.sh
bash macos/CLI/run-tests.sh
bash macos/Benchmarks/run-benchmarks.sh
xcodebuild -project macos/GrapeCompare.xcodeproj -scheme GrapeCompare \
  -destination 'platform=macOS' -configuration Debug build
```
