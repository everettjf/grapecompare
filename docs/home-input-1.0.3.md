# Automatic home input in 1.0.3

The home screen now presents one automatic drop area and a Choose Items button.
Manual file/folder slots, clipboard controls, and manual merge setup remain under
More Options. Recent comparisons and the demo menu remain available.

| Input | Result |
| --- | --- |
| Two files | Open file comparison immediately |
| Two folders | Open recursive folder comparison immediately |
| Three files | Confirm Base, Left, and Right, then open text/image merge |
| Files mixed with folders | Explain that mixed types are unsupported |
| Three folders | Explain that three-folder comparison is unsupported |
| Any other count | Explain the supported counts; never silently discard inputs |
| Missing files, symlinks, or remote URLs | Reject with an accessible-item message |

The filesystem determines input kind; a trailing slash is not evidence of a
folder. Dragged security scopes are held during inspection and merge setup,
released on cancellation, and retained by the workspace only for accepted work.
Choosing a different base or swapping sides does not write to source files.
Finder's exact-two-file App Intent is unchanged.

## Verification on 2026-09-30

- Core regression suite: 230 checks passed, including all routing cases above.
- Correctness audit, Simplified Chinese catalog and extracted-string coverage,
  icon checks, product-doc checks, sandbox and App Store metadata checks passed.
- Debug build passed with local ad-hoc signing and App Sandbox enabled.
- Release universal archive 1.0.3 (38) succeeded with normal project signing:
  `/tmp/GrapeCompare-1.0.3-38.xcarchive`.
- Archive validator passed: arm64/x86_64, macOS 15 minimum, sandbox, selected-file
  access, bookmarks, privacy manifest, no helper executables, and exact-two-file
  App Intent.
- Native UI automation repeatedly timed out while acquiring the app window.
  Visual layout, actual Finder drops, sheet role switching/cancellation, and the
  compact/light/dark/keyboard matrix still require interactive verification.

This is a prepared candidate. It has not been uploaded or submitted to App Store
Connect and does not change the currently approved App Store build.
