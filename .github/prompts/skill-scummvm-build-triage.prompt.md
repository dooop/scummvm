---
mode: agent
description: Diagnose and resolve build failures in the Swift ScummVM wrapper package. Use when swift build, Xcode, or CI reports compile, link, header, macro, or target-configuration errors in any target. Never modify upstream sources under ScummVMEngine/.
---

# ScummVM Build Triage

Follow this workflow to fix build failures quickly while preserving repository guardrails.

## Guardrails

- Never edit files under `ScummVMEngine/`.
- Prefer fixes in `Sources/ScummVM/`, `Sources/ScummVMiOS/`, `Sources/ScummVMmacOS/`, `Sources/ScummVMEngineOverrides/`, and `Package.swift`.
- Keep public API stable: `ScummVM`, `ScummVMView`, `ScummVMEngine`.

## Workflow

1. Capture the exact failing command and the first actionable error.
2. Classify the failure:
   - missing header/search path
   - macro/feature mismatch
   - platform-incompatible source
   - duplicate symbol or ODR conflict
   - missing library/slice link error
3. Select the smallest safe fix surface in this order:
   - wrapper/glue source
   - `Package.swift` flags, exclusions, dependencies, or resources
   - override translation unit in `Sources/ScummVMEngineOverrides/` plus matching upstream exclude in `Package.swift`
4. Apply a minimal patch and avoid broad refactors during triage.
5. Rebuild and verify the original error is gone and no new high-severity error replaces it.

## Common Checks

- Compare includes against `cxxSettings.headerSearchPath` in `Package.swift`.
- Validate platform conditionals (`iOS`, `tvOS`, `macOS`) before changing compile flags.
- For Objective-C macro collisions on macOS, check forced include headers in `Package.swift` before patching call sites.
- When adding an override file, ensure only one translation unit defines the symbol.

## Report Back

Always summarize:
- root cause
- exact files changed
- why this fix surface was chosen
- what build command(s) were run for verification
