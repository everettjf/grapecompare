# Changelog

## 1.0.0 — 2026-08-22

### Repository, image, sync, and Apple developer workflows

- Added a persistent Git repository library, worktree switching, upstream and merge-base context, paginated commit graph, tree changesets, cross-file navigation, and persistent review state.
- Added professional image Two-Up, One-Up, Split, Blink, and Difference modes with synchronized zoom/pan, navigator, pixel inspection, thresholds, channel isolation, bounded local alignment, and SVG rasterization.
- Added reusable folder ignore profiles, Mirror/Update/Custom synchronization plans, permission and extended-attribute comparison, machine-readable dry-run reports, CLI planning, and verified APFS clone-copy acceleration.
- Added semantic `.xcstrings` and section-aware `.pbxproj` comparison plus App Bundle, signature, entitlement, provisioning-profile, Mach-O, and Asset Catalog inspection.
- Retained the macOS 14 baseline and local-only processing; no compared content is uploaded.

## 1.15.0 — 2026-08-22

### Professional Git and release confidence

- Split HEAD-to-worktree changes into staged, unstaged, and untracked groups, including distinct comparisons when one path has both staged and unstaged edits.
- Added Git target shortcuts, keyboard commands, merge-parent selection, and rename-aware paginated file history.
- Added explicit text, binary, Git LFS pointer, submodule, and bounded large-file inspection without traversing submodules or requiring Git LFS.
- Bounded every changeset Git process with cancellation, a 30-second timeout, a 64 MiB output limit, and temporary-file-backed output capture.
- Coalesced 100-file watcher bursts and added deterministic fixtures for Git pagination, merge parents, binary/LFS/large files, submodules, cancellation, timeout, and output limits.
- Added a CI-built universal direct-distribution archive audit covering checksum, both CPU architectures, macOS 14 deployment, signature, sandbox separation, and English/Chinese resources.
- Expanded the performance gate to a 10,000-file mixed staged/unstaged repository and 200-commit paginated history.

## 1.14.0 — 2026-08-22

### Git changesets and file history

- Added a professional Git changeset workspace with path and status filters, commit context, and live-refresh timestamps.
- Added per-file commit history with author, date, subject, hash, and rename-aware paths.
- Added arbitrary A/B revision selection and comparison without checking out or changing the repository.
- Added deterministic Git metadata, history, unsafe-path, rename, and pre-rename materialization fixtures.
- Fixed persistent undo journals becoming unreadable under macOS 27 file-protection behavior while retaining atomic replacement.

## 1.13.0 — 2026-08-22

### Live comparisons and performance defenses

- Added layered FSEvents, vnode, and constant-cost root monitoring for active file, folder, merge, and Git comparisons.
- Coalesce filesystem bursts into one refresh, cancel superseded work, and never follow symbolic links while scanning.
- Pause live refresh when editable output is dirty so external changes cannot overwrite unsaved work.
- Added visible per-workspace live-update controls and lifecycle cleanup when tasks switch or close.
- Added reproducible performance budgets for large text and directory fixtures in CI.

## 1.12.0 — 2026-08-22

### Comparison workspaces

- Added window-local workspaces containing multiple independent file, folder, merge, or Git comparison tasks.
- Preserve each task's comparison state, output draft, merge decisions, cancellation, and file-operation controller while switching tasks.
- Protect unsaved output with an explicit discard confirmation and prevent closing tasks during active comparisons or file operations.
- Added accessible workspace tabs and menu commands for creating and closing comparison tasks.

## 1.11.0 — 2026-08-22

### Recent comparisons and safe resume

- Added a bounded recent-comparisons list for file, folder, merge, and Git workflows.
- Added single-session resume using versioned security-scoped bookmarks rather than raw paths.
- Revalidate every restored input and compare its current on-disk contents instead of persisting stale diff results.
- Never restore unsaved output text, merge decisions, or pending file operations across launches.

## 1.10.0 — 2026-08-22

### Professional merge workflow

- Added previous/next conflict navigation with persistent selection and accessible conflict status.
- Added keyboard commands for resolving the selected conflict as base, ours, theirs, or both, plus batch accept-ours and accept-theirs actions.
- Added undo and redo for individual and batch conflict-resolution decisions.
- Exposed every merge action in the macOS Merge menu with discoverable keyboard shortcuts.

## 1.9.0 — 2026-08-22

### Wider compatibility

- Lowered the minimum supported system to macOS 14 for the app, CLI, Git integration, and all comparison and merge workflows.
- Availability-gated the Finder Compare Files App Intent to macOS 15, where the required file-entity APIs are available.
- Updated CI, release validation, Homebrew metadata, and user documentation for the new compatibility boundary.

## 1.8.1 — 2026-08-22

### Compatibility and distribution

- Lowered the minimum supported system to macOS 15 while retaining the complete Finder, Git, CLI, and comparison workflows.
- Made direct-distribution releases universal for Apple silicon and Intel Macs and added minimum-version and architecture validation.
- Staple notarization tickets before packaging the final archive, then regenerate its checksum for reliable offline Gatekeeper verification.
- Aligned Homebrew, CI, issue templates, and English and Chinese documentation with the supported system range.

## 1.8.0 — 2026-08-02

### Text actions and merge

- Added search, line navigation, whitespace/case/line-ending rules, hunk-level left/right acceptance, editable output, safe changed-on-disk detection, unified patch export, wrapping, and source syntax colors.
- Added three-way base/ours/theirs merging with deterministic conflict blocks and explicit ours/theirs/both resolution.

### Developer and system integration

- Added a standalone `grapecompare` CLI for text diff/patch, merge, Git, image, JSON, and plist comparisons, including stable exit statuses and printable difftool/mergetool configuration.
- Added local branch, commit, index, and working-tree comparisons, including untracked files, without checkout or repository mutation.
- Added a two-file App Intent that can be exposed as a Finder Quick Action through Shortcuts.

### Images and structured data

- Added image side-by-side, overlay, and pixel heatmap views with size and difference metrics.
- Added semantic JSON and plist comparison with stable tree paths and key-order-independent object comparison.
- Added deterministic and randomized core coverage plus CLI integration tests for the new workflows.

## 1.4.0 — 2026-08-02

### Durable workflows

- Added an atomic, versioned operation journal so safe undo history survives app relaunches while retaining the same changed-output and collision checks.
- Added a native operation-history sheet with bounded retention and safe cleanup of private replacement backups; system Trash contents are never permanently deleted.
- Added security-scoped bookmark restoration for journaled operations on user-selected folders.

### Planning and progress

- Added explicit **Stop on First Failure** and **Continue After Failures** batch policies to the preflight review.
- Added throughput and estimated remaining time to execution and undo progress.
- Added import/export of `.grapeplan` recipes containing only validated relative paths, operation kinds, and source sides; imported paths are remapped to the current folder pair.

### Safety and quality

- Reject recipe path traversal, absolute paths, duplicate operation IDs, unsupported schemas, and intermediate symbolic-link escapes before changing the queue.
- Quarantine corrupt history files instead of overwriting them, serialize journal access across windows, and preserve newest-first stack semantics for undo.
- Added automated coverage for relaunch undo, changed-output protection after reload, retention, corruption recovery, both failure policies, deterministic ETA, and recipe validation.
- Added the complete v1.4 contract and acceptance gates in `docs/v1.4-durable-workflows.md`.

## 1.3.0 — 2026-08-02

### Safe file operations

- Added per-row and multi-selection left-to-right/right-to-left planning for copy, replace, and move, plus recoverable Move to Trash actions.
- Added a preflight review sheet with real hidden-item and byte counts, explicit destructive warnings, progress, cooperative cancellation, and per-item failures.
- Added transaction undo through the review sheet and Edit menu; overwrite backups and Trash locations are retained for the current app session.

### Safety

- Revalidate source and destination content immediately before every commit, and refuse undo when an output changed or its original location is occupied.
- Stage copies beside the destination, preserve symbolic links without following them, and remove incomplete staging data on cancellation.
- Implement cross-volume move as copy, byte-for-byte verification, destination commit, then source-to-Trash; serialize commits from multiple windows.
- Enabled read/write access only for folders explicitly selected by the user in the App Sandbox.

### Quality

- Added integration coverage for copy, replace, same- and cross-volume move, Trash, undo, stale plans, changed-output protection, hidden entries, symbolic links, and cancellation cleanup.
- Added the complete v1.3 safety contract and acceptance gates in `docs/v1.3-safe-operations.md`.

## 1.2.0 — 2026-08-02

### Reliability

- Cancelled superseded comparisons and prevented stale background work from overwriting newer results.
- Distinguished missing files from empty files and surfaced incomplete folder scans instead of silently skipping unreadable entries.
- Added a 256 MB text-materialization limit while preserving exact equality and binary checks.

### Experience

- Added horizontal navigation for long diff lines, repeatable difference jumps, keyboard navigation, and more accessible folder controls.
- Reduced SwiftUI invalidation with Observation, per-window comparison state, and cached visible folder rows.
- Added complete Simplified Chinese localization and stricter file/folder drop validation.

### Quality

- Added cancellation, missing/empty, size-limit, scan-error, and size-mismatch regression coverage.
- Added a full unsigned macOS Release build to CI.

## 1.1.0 — 2026-08-01

### Highlights

- Reworked the line-diff engine with dense Myers traces and low-occurrence anchors, improving high-churn performance while preserving stable structure.
- Reduced a representative 10,000-file folder comparison from about 2.385 seconds to about 0.382 seconds on the development machine.
- Added bounded parallel byte validation, reusable I/O buffers, and low-overhead POSIX directory scanning.
- Added memory-mapped large-file input and constant-time subtree status filtering.

### Accuracy

- Added explicit final-newline differences.
- Correctly preserves descendants when one side is a file and the other is a folder.
- Recursively compares package directories and compares symbolic links by target.
- Added 300 randomized shortest-edit-script checks plus large-file and large-folder stress coverage.

### Documentation

- Rebuilt the English and Chinese READMEs around screenshots, user benefits, reproducible benchmarks, installation, and validation.

## 1.0.0

- Initial macOS release with native file and folder comparison.
