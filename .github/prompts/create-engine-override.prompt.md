# Skill: Create an engine override

Use this skill when a build error requires changing an upstream source file under
`scummvm/`. Never edit that file directly — create a replacement under
`Sources/ScummVMEngineOverrides/` instead.

## Prerequisites
- You have the exact compiler error text.
- You have identified the upstream file that needs changing.

## Steps

### 1. Locate the upstream file
Note its path relative to `scummvm/`, e.g.
`scummvm/backends/platform/sdl/sdl.cpp`.

Read it and understand the minimal change needed to fix the error.

### 2. Determine the mirror path under ScummVMEngineOverrides/
Strip the `scummvm/` prefix and place the file under
`Sources/ScummVMEngineOverrides/` preserving subdirectory structure, e.g.
`Sources/ScummVMEngineOverrides/backends/platform/sdl/sdl.cpp`.

### 3. Create the override file
Copy the upstream file verbatim, then apply only the minimum change required.
- Do not reformat, rename symbols, or refactor.
- Do not add includes or logic beyond what the fix requires.
- Mark every change with a comment: `// OVERRIDE: <reason>`.

### 4. Exclude the upstream file in Package.swift
In the `ScummVMEngine` target's `exclude:` list, add the path relative to
`Sources/`, e.g.:
```swift
"scummvm/backends/platform/sdl/sdl.cpp",
```
Place the entry in the appropriate section of the exclusion list (grouped by
subsystem where possible).

### 5. Verify
- Confirm `Sources/ScummVMEngineOverrides/<path>` exists.
- Confirm the exclusion entry is present in `Package.swift`.
- Check that no other target also includes or excludes the same file.

### 6. Document
Add a comment above the exclusion entry in `Package.swift` that names the
override file and states the reason, so future maintainers know it exists:
```swift
// Overridden in ScummVMEngineOverrides: <reason>
"scummvm/backends/platform/sdl/sdl.cpp",
```

## Rules (non-negotiable)
- Never modify anything under `scummvm/`.
- Keep the override as a minimal diff from the upstream original.
- One override per upstream file — do not consolidate multiple files.
