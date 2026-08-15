# Swift package instructions

- `Package.swift` stays at the repository root and maps targets into this directory.
- Treat `Sources/ScummVMEngine` as read-only upstream through its `../../scummvm` symlink.
- Keep SwiftUI code in `Sources/ScummVM/`, platform glue in `Sources/ScummVMiOS/`, `Sources/ScummVMmacOS/`, and `Sources/ScummVMtvOS/`, and compatibility replacements in `Sources/ScummVMEngineOverrides/`.
- Pair every override with the exact upstream exclusion in the root `Package.swift`.
- Use `SCUMMVM_BUILD_FROM_SOURCE=1` for engine-facing work and publish a new engine release before expecting binary-mode consumers to receive it.
- Keep `README.md` current when package setup, lifecycle, resource layout, platform support, or release behavior changes.
- Apply the matching Swift skill from `../.agents/skills/` before changing package configuration, lifecycle glue, overrides, plugin tables, submodule integration, or XCFramework linkage.
