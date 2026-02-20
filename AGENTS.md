# Repository AGENTS.md

## Project goal
- Provide a thin SwiftUI wrapper around the upstream ScummVM codebase.
- Reuse as much upstream C/C++ as possible via the git submodule.
- Keep wrapper changes minimal and localized to the Swift/ObjC++ glue.

## Structure map
- `Package.swift` defines Swift Package targets, exclusions, and build flags.
- `Sources/ScummVMEngine/` is the upstream ScummVM git submodule (do not edit).
- `Sources/ScummVM/` contains SwiftUI wrappers (`ScummVM`, `ScummVMView`).
- `Sources/ScummVMEngine/` contains the engine target glue and overrides.
- `Sources/ScummVMEngineOverrides/` contains replacement translation units for build fixes.
- `Sources/ScummVMiOS/` and `Sources/ScummVMmacOS/` contain ObjC++ platform glue.
- `Sources/ScummVMiOS/include/ScummVMEngine.h` and `Sources/ScummVMmacOS/include/ScummVMEngine.h` are the public ObjC APIs.
- `Sources/ScummVMtvOS/` is a distinct tvOS glue target with its own requirements (not a copy of iOS).
- `Frameworks/` contains prebuilt XCFramework dependencies.

## Skills
- `scummvm-build-triage`: Diagnose build failures and choose the minimal fix surface. (`.agents/skills/scummvm-build-triage/SKILL.md`)
- `scummvm-override-workflow`: Add minimal override translation units with synchronized `Package.swift` exclusions. (`.agents/skills/scummvm-override-workflow/SKILL.md`)
- `objcxx-bridge-lifecycle`: Maintain SwiftUI/ObjC++ start-stop lifecycle and bridge threading rules. (`.agents/skills/objcxx-bridge-lifecycle/SKILL.md`)
- `plugins-table-maintainer`: Maintain plugin/detection override tables safely. (`.agents/skills/plugins-table-maintainer/SKILL.md`)
- `xcframework-linkage-check`: Diagnose linker failures and XCFramework slice/dependency mismatches. (`.agents/skills/xcframework-linkage-check/SKILL.md`)
- `scummvm-engine-architecture`: Map wrapper-to-engine architecture and change impact before patching. (`.agents/skills/scummvm-engine-architecture/SKILL.md`)
- `scummvm-submodule-sync`: Update Sources/ScummVMEngine, then reconcile override and exclusion drift safely. (`.agents/skills/scummvm-submodule-sync/SKILL.md`)
- `package-swift-auditor`: Audit Package.swift target membership, exclusions, binary targets, and platform conditions. (`.agents/skills/package-swift-auditor/SKILL.md`)

### Skill trigger rule
- If the user explicitly names one of the skills or the task clearly matches a skill description, open and apply that skill for the turn.

## Non-negotiable rules (read first)
- Never modify anything under `Sources/ScummVMEngine/`. It is a git submodule of upstream ScummVM.
- Never delete, reformat, or "fix" upstream sources. Keep upstream code intact.
- All changes must be in wrapper/glue code or in `Package.swift`.
- If a build issue requires source changes, add a replacement file in `Sources/ScummVMEngineOverrides/` and exclude the upstream file in `Package.swift`.

## Allowed edit surface
- SwiftUI wrapper code: `Sources/ScummVM/`
- ObjC++ glue: `Sources/ScummVMiOS/`, `Sources/ScummVMmacOS/`, `Sources/ScummVMtvOS/`
- Override translation units: `Sources/ScummVMEngineOverrides/`
- Build configuration: `Package.swift`
- Documentation: `README.md`
- Repository skills: `.agents/skills/`

## When build issues occur
- Capture the exact error text.
- First try fixes in wrappers or `Package.swift` (missing headers, flags, exclusions).
- Only if unavoidable: add a replacement file under `Sources/ScummVMEngineOverrides/` and exclude the upstream file in `Package.swift`.
- Overrides must be minimal diffs from the upstream original to make future resyncs tractable. Do not rewrite; change only what is necessary.

## Public API stability
- Keep public API small and stable (`ScummVM`, `ScummVMView`, `ScummVMEngine`).
- Do not add new public surface area without explicit user request.

## Build and platform expectations
- Supported platforms: iOS 14+, tvOS 14+, macOS 12+.
- Swift tools version: 6.0.
- The engine target links prebuilt XCFrameworks in `Frameworks/`.
- tvOS glue (`Sources/ScummVMtvOS/`) has distinct requirements from iOS and must be documented separately as it evolves.

## Threading and lifecycle (current state)
- The engine currently runs on the main thread.
- The goal is to support running the engine on a background thread; do not add main-thread assumptions that would block that migration.
- The `start`/`stop` SwiftUI lifecycle mechanism is not yet fully implemented and needs to be designed/adapted. Do not treat it as working.
- When designing glue code, keep thread-crossing explicit and minimal.

## Output expectations
- For reviews, list findings first, ordered by severity, with file links.
- Keep README in sync with setup steps, limitations, and known issues.
- Default to ASCII and keep comments minimal and focused.
