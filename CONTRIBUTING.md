# Contributing to GrapeCompare

Thanks for helping make file and folder comparison faster, clearer, and more reliable.

## Before you start

- Search [existing issues](https://github.com/everettjf/GrapeCompare/issues) before opening a new one.
- Use the bug or feature issue form and include a minimal, non-sensitive example when possible.
- For a large behavioral or architectural change, open an issue first so the approach can be discussed before substantial implementation work.
- Report vulnerabilities privately according to [SECURITY.md](SECURITY.md).

## Development setup

The application supports macOS 14 and later and requires Xcode 26 or later to build. The Finder App Intent is availability-gated to macOS 15. Open `macos/GrapeCompare.xcodeproj`, select the `GrapeCompare` scheme, and run the app.

The comparison engines and their tests can also be compiled directly with the Swift toolchain:

```bash
bash macos/Tests/run-tests.sh
```

Run the reproducible Release benchmark with:

```bash
bash macos/Benchmarks/run-benchmarks.sh
```

Optional arguments set generated line and file counts:

```bash
bash macos/Benchmarks/run-benchmarks.sh 100000 50000
```

## Pull requests

Keep each pull request focused and explain the user-facing motivation. Before submitting:

1. Run the full core test suite.
2. Add regression coverage for correctness fixes and edge cases.
3. Manually exercise affected SwiftUI workflows.
4. Update both English and Chinese READMEs for user-facing documentation changes.
5. Include screenshots for visible UI changes.
6. Include the exact fixture, command, and before/after timings for performance changes.

Comparison accuracy takes priority over benchmark gains. An optimization should retain exact byte validation where required and must not silently discard stable diff structure.

## Code style

Follow the surrounding Swift style, favor small focused types and functions, and keep platform-independent comparison logic in `macos/GrapeCompare/Core`. Avoid unrelated formatting changes in the same pull request.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
