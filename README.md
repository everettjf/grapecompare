<div align="center">
  <img src="macos/GrapeCompare/Assets.xcassets/GrapeIcon.imageset/grape-icon.png" width="112" alt="GrapeCompare app icon">

# GrapeCompare

**Fast, accurate file and folder comparison for macOS.**<br>
A native SwiftUI app inspired by Beyond Compare — no WebView, no cloud upload.

[![Release](https://img.shields.io/github/v/release/everettjf/GrapeCompare?display_name=tag&sort=semver&style=flat-square&color=7c3aed)](https://github.com/everettjf/GrapeCompare/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/everettjf/GrapeCompare/ci.yml?branch=main&style=flat-square&label=tests)](https://github.com/everettjf/GrapeCompare/actions/workflows/ci.yml)
![macOS](https://img.shields.io/badge/macOS-27%2B-111827?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)

[Mac App Store](https://apps.apple.com/app/id6796778424) · [Website](https://xnu.app/GrapeCompare/) · [中文说明](README.zh-CN.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

</div>

## See every difference clearly

### Folder comparison

Browse a recursive, filterable tree and jump directly from a changed file into its text diff.

<p align="center">
  <img src="docs/assets/folder-diff.png" width="100%" alt="GrapeCompare folder comparison showing a recursive result tree and status filters">
</p>

### File comparison

Review aligned lines, character-level edits, totals, and previous/next difference navigation side by side.

<p align="center">
  <img src="docs/assets/file-diff.png" width="100%" alt="GrapeCompare side-by-side file comparison with inline highlights">
</p>

## Why GrapeCompare

- **Accurate:** byte-exact folder validation, shortest edit scripts for normal changes, visible final-newline differences, and correct handling of symbolic links, packages, and file/folder conflicts.
- **Fast at scale:** 100,000-line text comparisons complete in about 0.06 seconds; a 10,000-file folder benchmark completes in about 0.38 seconds on the development machine.
- **Easy to read:** side-by-side lines, character-level highlights, aligned line numbers, difference counts, and previous/next navigation.
- **Native and private:** a responsive macOS interface, Dark and Light appearances, local-only processing, and read-only access to user-selected files.

## Features

### File comparison

- Adaptive Myers line diff with low-occurrence anchors for large rewrites
- Character-level highlighting inside modified lines
- Added, removed, and modified counts with keyboard-friendly navigation
- CRLF/LF normalization, final-newline reporting, and binary-file detection
- Memory-mapped input to avoid duplicating large files in memory

### Folder comparison

- Recursive expandable tree with **Same**, **Different**, **Left Only**, and **Right Only** states
- All/Differences/Left Only/Right Only filters with automatic expansion of changed folders
- Type and size prechecks followed by exact, bounded-parallel byte validation
- Correct traversal of package directories and comparison of symbolic-link targets
- Fast subtree filtering through pre-aggregated status indexes

## Performance

The repository includes a Release benchmark with reproducible generated fixtures. Representative results from the development machine:

| Scenario | Result | Notes |
| --- | ---: | --- |
| 100k-line sparse edit | **0.060 s** | End-to-end: split, diff, inline ranges, rows |
| 30k-line high churn | **0.070 s** | Retains all stable structural anchors |
| 10k-file folder | **0.382 s** | Down from 2.385 s, about **6.2× faster** |
| 50k-file folder | **3.917 s** | Full scan, validation, tree, sort, rollup |

Timings exclude fixture generation and vary by hardware and storage. Run them locally:

```bash
bash macos/Benchmarks/run-benchmarks.sh
bash macos/Benchmarks/run-benchmarks.sh 100000 50000
```

The diff design builds on [Myers' O(ND) algorithm](https://doi.org/10.1007/BF01840446) and the low-occurrence anchoring ideas documented in [Git's diff algorithms](https://git-scm.com/docs/diff-algorithm-option.html).

## Install

Install the signed release from the [Mac App Store](https://apps.apple.com/app/id6796778424).

To build from source, use macOS 27+ and Xcode 27+:

```bash
xcodebuild -project macos/GrapeCompare.xcodeproj \
  -scheme GrapeCompare \
  -destination 'platform=macOS' \
  -configuration Debug build
```

You can also open `macos/GrapeCompare.xcodeproj` in Xcode and press Run.

## Command line

```bash
GrapeCompare <left> <right>
```

Two folders open the folder comparison; other inputs open the file comparison. The App Store build is sandboxed and cannot read arbitrary command-line paths. Build with App Sandbox disabled if this workflow is required.

## Development

Run the platform-independent core suite without launching Xcode:

```bash
bash macos/Tests/run-tests.sh
```

The suite contains 45 focused checks, 300 randomized shortest-edit-script cases, large-text stress cases, and folder edge cases. Pull requests run the same suite in GitHub Actions.

```text
macos/
├── GrapeCompare/
│   ├── Core/
│   │   ├── DiffEngine.swift       # adaptive Myers + low-occurrence anchors
│   │   └── FolderComparator.swift # POSIX scan + bounded exact validation
│   ├── Views/                     # native SwiftUI file/folder interfaces
│   └── AppState.swift             # comparison orchestration
├── Tests/                         # deterministic correctness and stress tests
└── Benchmarks/                    # repeatable large-file/folder benchmarks
```

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. For help, use [GitHub Issues](https://github.com/everettjf/GrapeCompare/issues); report security problems according to [SECURITY.md](SECURITY.md). By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
