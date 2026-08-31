# Repository Guidelines

GrapeCompare is a sandboxed Mac App Store file and folder comparison app with a reusable Swift core. Correctness and filesystem safety take priority over visual similarity to other diff tools.

## Structure

- `macos/GrapeCompare/Core`: comparison engine, folder scanner, and transactional file operations.
- `macos/GrapeCompare/Views`: SwiftUI application UI.
- `macos/Tests`: deterministic, randomized, stress, and filesystem tests.
- `macos/Benchmarks`: repeatable performance scenarios.

## Verification

```bash
bash macos/Tests/run-tests.sh
xcodebuild -project macos/GrapeCompare.xcodeproj -scheme GrapeCompare \
  -destination 'platform=macOS' -configuration Debug build
```

Every new feature or bug fix must add or extend a repeatable local test. Run the
focused regression first, then the complete core, localization, sandbox audit, and Xcode
build checks before release. Do not rely on GitHub Actions for product quality.

## Delivery

Every completed user-facing change must be committed, pushed, archived with App
Sandbox enabled, and prepared for a new Mac App Store version. Validate the
archive's entitlements and embedded content before uploading it through Xcode or
App Store Connect. Never create or publish a non-sandboxed product build.

After pushing, inspect the repository's GitHub checks. Fix any failure before
declaring delivery complete. Product CI and release automation intentionally run
locally; GitHub Actions is reserved for GitHub Pages deployment.

## Conventions

- Preserve shortest-edit-script correctness and transactional file-operation guarantees.
- Do not follow symlinks or mutate files without explicit, validated intent.
- Bound parallel directory work and memory usage on large inputs.
- Add a regression fixture for every parser, merge, Unicode, permission, or filesystem bug.
- Preserve App Sandbox and security-scoped access in every configuration.

Update benchmarks and user docs when performance or product behavior changes. Canonical repository: `https://github.com/everettjf/grapecompare`.
