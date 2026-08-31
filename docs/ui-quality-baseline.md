# UI quality baseline

Every user-facing UI change is reviewed against the same macOS presentation
matrix. The goal is to keep dense comparison workflows readable without
trading away filesystem safety or keyboard access.

## Window matrix

| Name | Size | Purpose |
| --- | --- | --- |
| Compact | 720 × 560 | Minimum supported workspace |
| Default | 1120 × 740 | New-window presentation |
| Wide | 1440 × 900 | Long paths and dense comparisons |

## Appearance matrix

- Light and Dark appearances.
- Increase Contrast enabled.
- Differentiate Without Color enabled.
- Reduce Motion enabled.
- Keyboard-only navigation with Full Keyboard Access.

## Required screens

- Home: empty inputs, populated inputs, recent comparisons, invalid drop.
- File comparison: equal, changed, binary, oversized, loading, and error.
- Folder comparison: mixed states, selection, queued plan, refresh, empty,
  filtered-empty, and error.
- Merge: unresolved conflict, resolved conflict, dirty output, and image merge.
- File operation review/history: ready, executing, failure, undo, and empty.

## Review rules

1. Primary content remains visible at the compact size without horizontal
   clipping of essential actions.
2. Color is reinforced by a symbol or text label.
3. Selection, current difference, search match, and semantic diff state remain
   distinguishable when they overlap.
4. Icon-only controls have a tooltip and accessibility label.
5. Loading preserves existing results when possible and never looks disabled.
6. Destructive file operations remain separated from navigation and comparison
   controls and still require the existing review flow.

The checked-in documentation screenshots are the initial file and folder
comparison references. Update them intentionally when those screens change.
