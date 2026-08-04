# Repository Guidelines

GrapeCompare is a native macOS file and folder comparison app with a reusable Swift core and CLI. Correctness and filesystem safety take priority over visual similarity to other diff tools.

## Structure

- `macos/GrapeCompare/Core`: comparison engine, folder scanner, and transactional file operations.
- `macos/GrapeCompare/Views`: SwiftUI application UI.
- `macos/Tests`: deterministic, randomized, stress, and filesystem tests.
- `macos/CLI`: command-line diff and merge frontend.
- `macos/Benchmarks`: repeatable performance scenarios.

## Verification

```bash
bash macos/Tests/run-tests.sh
bash macos/CLI/run-tests.sh
xcodebuild -project macos/GrapeCompare.xcodeproj -scheme GrapeCompare \
  -destination 'platform=macOS' -configuration Debug build
```

## Conventions

- Preserve shortest-edit-script correctness and transactional file-operation guarantees.
- Do not follow symlinks or mutate files without explicit, validated intent.
- Bound parallel directory work and memory usage on large inputs.
- Add a regression fixture for every parser, merge, Unicode, permission, or filesystem bug.
- Keep App Store sandbox limitations distinct from direct-distribution capabilities.

Update benchmarks and user docs when performance or CLI behavior changes. Canonical repository: `https://github.com/everettjf/grapecompare`.
