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

## Input and structured-filter regression (1.0.2)

Repeat at 720 × 560 and 1120 × 740, in English and Simplified Chinese:

1. Home: verify Left/Right and Base/Ours/Theirs labels remain visible. Select a file, choose a replacement, then cancel the panel: the original selection must remain. Reopen the panel and confirm another file; only that slot changes. Hover a long path to read it in full.
2. Drop two files onto one slot: the unsupported-item alert must explain Quick Compare; the existing selection must remain intact.
3. Drop three files onto Quick Compare. Use keyboard navigation (enable macOS Keyboard Navigation) and Space to select two checkboxes. Other unchecked items become disabled; deselect one to change the pair. Check that Left/Right follows selection order and Cancel dismisses without opening a comparison.
4. Compare JSON files with changed, added, and removed values. Search for a path, an old value, and a new value. Verify matching/total counts. Search for a nonexistent value: show No Matching Differences, never the equivalent-documents state. Clear Filter must restore all rows without moving the comparison toolbar. Whitespace-only input must show all rows.
5. Compare equivalent JSON: the equivalent-documents state must remain distinct from filtered empty results. Hover a truncated value to read its full text.
