---
name: xcframework-linkage-check
description: Diagnose XCFramework and native library linkage issues in the ScummVM Swift package. Use when builds fail with undefined symbols, missing architectures, invalid slices, or platform-specific linker errors involving swift/Frameworks/ and Package.swift dependencies.
---

# XCFramework Linkage Check

Use this workflow for link-time and binary-compatibility failures.

## Workflow

1. Capture exact linker error symbols and the target/platform tuple.
2. Map each missing symbol to expected provider:
- prebuilt XCFramework
- C/C++ package target dependency
- platform backend source
3. Verify package linkage configuration in `Package.swift`:
- target dependency list
- platform conditions
- excluded files impacting symbol providers
4. Verify binary compatibility:
- required platform slices exist
- architecture slice exists for build destination
- deployment target is compatible
5. Apply minimal dependency/config changes and rebuild.

## Guardrails

- Do not patch upstream source to work around a missing library.
- Keep dependency additions explicit and target-scoped.
- Prefer correcting link graph over adding broad unsafe flags.

## Useful Checks

- Inspect `.xcframework` `Info.plist` for available slices.
- Use `lipo -info` on selected binaries when slice issues are suspected.
- Re-check conditional dependencies for macOS-only SDL links.

## Report Back

State missing symbol class, owning binary/library, and exact package change that fixed linkage.
