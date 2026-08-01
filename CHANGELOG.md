# Changelog

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
