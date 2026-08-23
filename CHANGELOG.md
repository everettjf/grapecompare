# Changelog

## 1.0.4 — Unreleased

### Polish and performance

- Move full-resolution image difference recalculation out of SwiftUI rendering, debounce option changes, and expose progress without blocking interaction.
- Add standard image zoom keyboard shortcuts, explicit accessibility values, and reduced-motion behavior.

## 1.0.3 — Unreleased

### Images, folders, and system integration

- Add distinct Fit and Actual Pixels image zoom controls, a visible zoom readout, and reduced-motion-safe blink comparison.
- Add a persistent custom folder ignore profile alongside the built-in developer profile.
- Accept exactly two files or folders from Finder/Open With and add `grapecompare://compare?left=…&right=…` deep-link handling.

## 1.0.2 — Unreleased

### Git review and merge parity

- Add durable local review notes, reviewed-file progress, and one-click comparison with the previous file revision.
- Add merge-resolution progress and prevent export or mergetool completion while standard conflict markers remain in editable output.

## 1.0.1 — Unreleased

### Reliability

- Release security-scoped bookmark access when a comparison workspace closes and avoid retaining duplicate access for the same restored path.
- Cancel active comparison, Git-history, and filesystem-watch work before releasing a closed workspace.
- Keep the 10,000-file Git changeset and 200-commit history performance fixtures independent so CI measures both dimensions deterministically.

## 1.0.0 — 2026-08-22

### First public release

- Added native two-way file and folder comparison, character-level differences, editable output, patch export, and three-way merge.
- Added Git repository workflows, difftool and mergetool integration, commit history, worktrees, merge-base context, and persistent review state.
- Added professional image comparison modes with synchronized zoom and pan, pixel inspection, thresholds, channel isolation, local alignment, SVG rasterization, and heatmaps.
- Added safe folder synchronization plans, reusable ignore profiles, metadata comparison, dry-run reports, transactional operations, persistent undo, and APFS clone-copy acceleration.
- Added semantic JSON, plist, XCStrings, and Xcode project comparison plus App Bundle, signature, entitlement, provisioning-profile, Mach-O, and Asset Catalog inspection.
- Added Finder Quick Action and standalone CLI workflows.
- Added deterministic, randomized, filesystem, stress, correctness, and repeatable performance coverage.
- Supports macOS 14 and later on Apple silicon and Intel Macs, with local-only processing and no subscription.
