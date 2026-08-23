# Changelog

## 1.0.8 — 2026-08-23

### Automation and verifiable quality

- Add stable JSON output for CLI text, merge, structured-data, image, and Git comparisons while retaining meaningful exit statuses.
- Add a single correctness-audit command that records core, CLI, real-Git, localization, and website-screenshot checks in a machine-readable report.
- Publish the correctness and screenshot audit report as a CI artifact for every push and pull request.

## 1.0.7 — 2026-08-23

### Professional inspection workflows

- Preview selected folder-comparison items with macOS Quick Look, including the Space bar shortcut.
- Open either compared file in its default editor or reveal it in Finder.
- Ignore changes to unquoted C-style, shell, or single-line HTML comment text without treating quoted URL fragments as comments.
- Inspect image format, dimensions, encoded size, color model, profile, bit depth, alpha, and resolution.
- Lock a pixel sample while navigating and inspect its RGBA, HSB, and CIELAB values.

## 1.0.6 — 2026-08-23

### Git workflow

- Compare the current working tree with the repository state from 24 hours, 7 days, or 30 days ago.
- Identify files that have both staged and unstaged changes as partially staged.
- Open a commit-wide changeset directly from file history or the commit graph.
- Reveal the active repository in Finder or open it in Terminal.

## 1.0.5 — 2026-08-23

### Real-world performance validation

- Add a reusable benchmark for comparing arbitrary, already-extracted directory trees.
- Validate exact comparison of LLVM 21.1.8 and 22.1.8 source trees: up to roughly 170,000 leaves and 2.3 GiB per tree in about 9.6 seconds with stable results.
- Cross-check all LLVM comparison counts with an independent chunk comparator.

## 1.0.4 — 2026-08-23

### Polish and performance

- Move full-resolution image difference recalculation out of SwiftUI rendering, debounce option changes, and expose progress without blocking interaction.
- Add standard image zoom keyboard shortcuts, explicit accessibility values, and reduced-motion behavior.

### Images, folders, and system integration

- Add distinct Fit and Actual Pixels image zoom controls, a visible zoom readout, and reduced-motion-safe blink comparison.
- Add a persistent custom folder ignore profile alongside the built-in developer profile.
- Accept exactly two files or folders from Finder/Open With and add `grapecompare://compare?left=…&right=…` deep-link handling.

### Git review and merge parity

- Add durable local review notes, reviewed-file progress, and one-click comparison with the previous file revision.
- Add merge-resolution progress and prevent export or mergetool completion while standard conflict markers remain in editable output.

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
