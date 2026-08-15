---
name: package-swift-auditor
description: Audit Package.swift consistency for target membership, exclusions, binary targets, and platform conditions in this ScummVM wrapper. Use when editing Package.swift, adding overrides or frameworks, after submodule updates, or when package resolution or build errors suggest manifest drift.
---

# Package.swift Auditor

Validate manifest integrity before and after wrapper-side build changes.

## Guardrails

- Never modify files under `scummvm/`.
- Prefer minimal manifest edits that preserve existing target boundaries.
- Treat override and exclusion mismatches as correctness bugs, not cleanup tasks.

## Workflow

1. Parse the manifest with `swift package dump-package > /dev/null` before patching.
2. Validate target boundaries so SwiftUI, platform glue, and engine override sources remain in their intended targets.
3. Audit exclusion paths for exactness, stale upstream references, and one-to-one pairing with active overrides.
4. Audit engine dependency names against `.binaryTarget` declarations; for path-based targets, confirm the referenced `swift/Frameworks/*.xcframework` exists.
5. Audit platform and toolchain constraints (`iOS 17+`, `tvOS 17+`, `macOS 15+`, `swift-tools-version:6.0`) for accidental drift.
6. Re-run the build command associated with the manifest change to verify the manifest fix resolves the real failure.

## Useful Checks

- `swift package describe`
- `rg 'path: "swift/' Package.swift`
- `rg "ScummVMEngineOverrides/" Package.swift`
- `find swift/Sources/ScummVMEngineOverrides -type f`

## Report Back

List manifest issues found, exact files and lines changed, and validation commands executed.
