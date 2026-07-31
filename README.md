# GrapeCompare

[中文版 README](README.zh-CN.md)

A native macOS file & folder comparison tool inspired by Beyond Compare — written in pure SwiftUI, no WebView.

## Features

### Folder Compare
- Recursively compares two folders and shows the result as an expandable tree
- Per-item status: **Same / Different / Left Only / Right Only**, with folder status rolled up from descendants
- Filters (All / Differences / Left Only / Right Only), size columns, and a summary status bar
- Folders containing differences are auto-expanded; double-click a file to open its diff
- Files are compared by size first, then by streaming 1 MB chunk comparison — no large-file memory spikes

### File Compare
- Side-by-side diff with line-level highlighting (red/green) and **in-line character-level highlighting** for modified lines
- Line numbers, aligned blank placeholders, binary-file detection, and an "identical files" state
- Difference statistics (`+added −removed ~modified`) and previous/next difference navigation
- Myers O(ND) line diff with common prefix/suffix trimming and an edit-distance guard, so huge files with few changes diff in milliseconds (100k lines in ~0.05 s)

### General
- Polished UI in both Dark and Light mode, drag & drop or click-to-choose inputs
- Command line usage, similar to `bcompare`:

  ```bash
  GrapeCompare <left> <right>   # two folders → folder compare, otherwise → file compare
  ```

## Requirements

- macOS 27+, Xcode 27+

## Build & Run

Open `macos/GrapeCompare.xcodeproj` in Xcode and run, or:

```bash
xcodebuild -project macos/GrapeCompare.xcodeproj -scheme GrapeCompare \
    -destination 'platform=macOS' -configuration Debug build
```

## Tests

The UI-independent core (`DiffEngine`, `FolderComparator`) has a self-contained test harness:

```bash
macos/Tests/run-tests.sh   # compiles with swiftc and runs 29 assertions
```

## Project Layout

```
macos/
├── GrapeCompare/
│   ├── GrapeCompareApp.swift      # @main entry point
│   ├── AppState.swift             # app state, compare orchestration, CLI args
│   ├── Core/
│   │   ├── DiffEngine.swift       # Myers line diff + aligned rows + in-line ranges
│   │   └── FolderComparator.swift # recursive folder scan + streaming file compare
│   └── Views/
│       ├── HomeView.swift         # mode picker with drag & drop slots
│       ├── FileDiffView.swift     # side-by-side diff
│       ├── FolderCompareView.swift# folder tree
│       └── Theme.swift            # shared colors & fonts
└── Tests/
    ├── main.swift                 # core test harness
    └── run-tests.sh
```

## Notes

- App Sandbox is disabled so the CLI can read arbitrary paths (same trade-off as Beyond Compare). Re-enable it if you plan to distribute via the App Store.
