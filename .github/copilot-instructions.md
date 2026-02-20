# Copilot instructions

## Project goal
- Provide a thin SwiftUI wrapper around the upstream ScummVM codebase.
- Reuse as much upstream C/C++ as possible via the git submodule.
- Keep wrapper changes minimal and localized to the Swift/ObjC++ glue.

## Structure map
- `Package.swift` defines Swift Package targets, exclusions, and build flags.
- `ScummVMEngine/` is the upstream ScummVM git submodule (do not edit).
- `Sources/ScummVM/` contains SwiftUI wrappers (`ScummVM`, `ScummVMView`).
- `Sources/ScummVMEngine/` contains the engine target glue and overrides.
- `Sources/ScummVMEngineOverrides/` contains replacement translation units for build fixes.
- `Sources/ScummVMiOS/` and `Sources/ScummVMmacOS/` contain ObjC++ platform glue.
- `Sources/ScummVMiOS/include/ScummVMEngine.h` and `Sources/ScummVMmacOS/include/ScummVMEngine.h` are the public ObjC APIs.
- `Sources/ScummVMtvOS/` is a distinct tvOS glue target with its own requirements (not a copy of iOS).
- `Frameworks/` contains prebuilt XCFramework dependencies.

## Non-negotiable rules (read first)
- Never modify anything under `ScummVMEngine/`. It is a git submodule of upstream ScummVM.
- Never delete, reformat, or "fix" upstream sources. Keep upstream code intact.
- All changes must be in wrapper/glue code or in `Package.swift`.
- If a build issue requires source changes, add a replacement file in `Sources/ScummVMEngineOverrides/` and exclude the upstream file in `Package.swift`.

## Allowed edit surface
- SwiftUI wrapper code: `Sources/ScummVM/`
- ObjC++ glue: `Sources/ScummVMiOS/`, `Sources/ScummVMmacOS/`, `Sources/ScummVMtvOS/`
- Override translation units: `Sources/ScummVMEngineOverrides/`
- Build configuration: `Package.swift`
- Documentation: `README.md`

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

## Skill routing
Detailed workflows live in `.github/prompts/`. Apply the corresponding skill when the task matches:

| Task context | Skill prompt |
|---|---|
| Build failure (compile, link, header, macro) | `skill-scummvm-build-triage` |
| Creating or updating an override in `Sources/ScummVMEngineOverrides/` | `skill-scummvm-override-workflow` |
| Editing `Sources/ScummVM/`, `Sources/ScummVMiOS/`, `Sources/ScummVMmacOS/`, `Sources/ScummVMtvOS/` lifecycle/bridge code | `skill-objcxx-bridge-lifecycle` |
| Editing `plugins_table.h` or `detection_table.h` | `skill-plugins-table-maintainer` |
| Reviewing or planning architecture-level changes | `skill-scummvm-engine-architecture` |
| Undefined symbol / missing slice / linker errors involving `Frameworks/` | `skill-xcframework-linkage-check` |
| Updating `Sources/ScummVMEngine` to a newer upstream commit | `skill-scummvm-submodule-sync` |
| Reviewing `Package.swift` for target/exclusion/dependency consistency | `skill-package-swift-auditor` |

Read the matching skill prompt before making changes in that area.
