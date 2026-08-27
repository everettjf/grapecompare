# Changelog

## 1.0.25 — 2026-08-26

### Stable folder status badges

- Keep folder comparison status badges on one line at the default and compact window sizes.
- Give the central status-and-actions column enough width for its label and directional controls.
- Add a regression policy check for the reviewed folder status column width.

## 1.0.24 — 2026-08-26

### Comprehensive UI refinement

- Establish shared design tokens and a repeatable UI quality baseline for compact, default, wide, light, and dark presentations.
- Simplify the comparison home, unify comparison top bars, and improve text-diff readability and navigation.
- Clarify folder comparison states, interaction feedback, Reduce Motion behavior, and accessibility semantics.

## 1.0.23 — 2026-08-25

### Balanced comparison workspace

- Rebuild the home screen around symmetric file and folder entry cards, an equal-width workflow row, and a quieter full-width continuation strip for recent comparisons.
- Adapt the folder-comparison toolbar to compact windows and consolidate comparison, synchronization, and plan controls into focused menus.
- Separate folder status from queued actions, reveal row operations on hover, and add a contextual action bar for multi-selection.
- Highlight the current text difference with a persistent focus outline and add a compact document overview for all added, removed, and modified rows.
- Make difference statistics readable without relying on color, expose full paths through tooltips and context menus, and add configurable code size and row density.
- Add Simplified Chinese translations and regression coverage for the new comparison-presentation policies.

## 1.0.22 — 2026-08-24

### Compact file-comparison workspace

- Lower the app content minimum width from 860 to 720 points.
- Adapt both file-comparison toolbars automatically instead of forcing horizontal overflow.
- Keep search, difference and hunk navigation, and side selection visible at compact widths.
- Consolidate rules, wrapping, output, patch export, filenames, and external-editor actions into compact menus when space is constrained.

## 1.0.21 — 2026-08-24

### Single-tab New Comparison access

- Keep the single-tab workspace chrome compact while exposing New Comparison in the native title-bar toolbar.
- Make Command-N create a comparison tab instead of opening a separate macOS window.
- Avoid duplicate add buttons after the multi-tab bar becomes visible.

## 1.0.20 — 2026-08-24

### Cleaner window chrome and rounded icon

- Hide the custom workspace tab bar when only one comparison is open, restoring the reclaimed vertical space to the comparison content.
- Reveal the tab bar automatically when a second comparison is created with New Comparison.
- Give every macOS app-icon size transparent rounded corners instead of opaque black corner pixels.
- Keep the README and website icon assets consistent and validate icon dimensions and transparency locally.

## 1.0.19 — 2026-08-24

### Reliable folder drag and drop

- Make the full left and right comparison slots reliable drag targets, including their transparent padding.
- Use independent URL drop destinations so either folder slot accepts its own Finder drop consistently.
- Validate dropped and picker-selected inputs against their real filesystem type without following symbolic links.
- Add repeatable regression coverage for folders, regular files, missing paths, mismatched inputs, and symbolic links.

## 1.0.18 — 2026-08-24

### Local-first release discipline

- Make repeatable local regression coverage mandatory for every feature and bug fix.
- Move product verification and Homebrew delivery fully to the signed, notarized local release process.
- Remove redundant GitHub product CI and release workflows while retaining GitHub Pages deployment.
- Stabilize the exact-file watcher regression test against checkpoint-adjacent startup events.

## 1.0.17 — 2026-08-24

### Stable folder browsing and JSON source comparison

- Keep completed folder results visible during live refreshes and show refresh progress without replacing the page.
- Prevent folder rows from expanding to the full list height and leaving a large blank area.
- Switch JSON comparisons between semantic field differences and the original side-by-side source diff.

## 1.0.16 — 2026-08-24

### Stable live file comparison

- Keep the last completed file diff visible while a live refresh runs, avoiding full-page flicker.
- Ignore filesystem events caused by sibling files when watching an exact comparison input.

## 1.0.15 — 2026-08-23

### Refined home workspace and pixel-art identity

- Reorganize the home screen into a focused two-column comparison workspace with clearer primary and advanced workflows.
- Improve information density, keyboard and accessibility grouping, compact-window scrolling, and Simplified Chinese localization.
- Introduce a distinctive two-cluster pixel-art grape icon that represents side-by-side comparison.
- Provide the new icon at every required macOS AppIcon resolution from 16 to 1,024 pixels.

## 1.0.14 — 2026-08-23

### Image conflict resolution

- Detect three-image merge inputs and present Base, Ours, and Theirs as full visual candidates.
- Measure Base-to-Ours and Base-to-Theirs pixel differences with the existing deterministic image engine.
- Export the selected original image bytes without re-encoding or color-profile loss.
- Complete Git image mergetool requests atomically and create the success sentinel only after the selected bytes are written.

## 1.0.13 — 2026-08-23

### Quick drop and clipboard comparison

- Drop exactly two files or two folders on one target to start the matching comparison immediately.
- Paste file URLs or bounded text independently into the left and right file inputs; comparison starts as soon as both sides are ready.
- Store pasted text in private `0700` temporary directories with `0600` files and an 8 MiB per-item safety limit.
- Reject mixed file/folder pairs and ambiguous item counts before starting any filesystem work.

## 1.0.12 — 2026-08-23

### Printable and shareable comparison reports

- Print file, folder, merge, and Git comparisons through the native macOS print panel.
- Export the same paginated report as PDF or send it through the system sharing picker.
- Include comparison targets, deterministic summaries, and detailed rows without relying on a screenshot of the current viewport.
- Bound report generation to 20,000 lines and 8 MiB, and mark truncated reports explicitly for safe large-input behavior.

## 1.0.11 — 2026-08-23

### Live Git review and contextual actions

- Persist the live-refresh preference and add a separate opt-in Git notification preference.
- Notify after coalesced working-copy refreshes using only the repository name and filesystem-event count, never file contents.
- Add changeset actions for comparing, opening file history, copying paths or bounded UTF-8 contents, saving a copy, opening externally, and revealing working-tree files in Finder.
- Enforce an 8 MiB content-action limit and keep Git path validation, command timeouts, and output limits in effect.
- Validate source-extracted localization coverage and fill previously missing Simplified Chinese image and ignore-profile strings.

## 1.0.10 — 2026-08-23

### Reusable text filters

- Ignore volatile timestamps, UUIDs, and hexadecimal memory addresses without modifying source text or exact-identity results.
- Add any number of custom regular-expression filters with validation before applying them.
- Persist the complete comparison-rule profile for reuse across files and app launches.
- Precompile filters once per comparison and combine built-in rules into one scan; the 100,000-line worst-case filter benchmark completes in about 0.84 seconds.

## 1.0.9 — 2026-08-23

### Image comparison precision

- Render image differences at absolute intensity or proportionally to the measured channel change.
- Configure the colors and opacity used for different and identical pixels without changing deterministic difference counts.
- Keep a visible crosshair on a locked pixel sample while zooming, panning, or changing image views.
- Preserve 1,024×1,024 RGBA comparison performance at approximately 0.005 seconds in the release benchmark.

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
