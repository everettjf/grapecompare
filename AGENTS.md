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

Every new feature or bug fix must add or extend a repeatable local test. Run the
focused regression first, then the complete core, CLI, localization, and Xcode
build checks before release. Do not rely on GitHub Actions for product quality.

## Delivery

Every completed user-facing change must be committed, pushed, and released as a
new Homebrew version. Build the Universal direct-distribution app locally, sign
it with Developer ID, submit it to Apple notarization, staple the ticket, run
`scripts/validate-release.sh`, and require Gatekeeper to report `Notarized
Developer ID`. Publish the final zip and checksum as a GitHub Release, update
`everettjf/homebrew-tap`, then refresh the tap locally and confirm `brew info`
shows the new version.

After pushing, inspect the repository's GitHub checks. Fix any failure before
declaring delivery complete. Product CI and release automation intentionally run
locally; GitHub Actions is reserved for GitHub Pages deployment.

## Conventions

- Preserve shortest-edit-script correctness and transactional file-operation guarantees.
- Do not follow symlinks or mutate files without explicit, validated intent.
- Bound parallel directory work and memory usage on large inputs.
- Add a regression fixture for every parser, merge, Unicode, permission, or filesystem bug.
- Keep App Store sandbox limitations distinct from direct-distribution capabilities.

Update benchmarks and user docs when performance or CLI behavior changes. Canonical repository: `https://github.com/everettjf/grapecompare`.
