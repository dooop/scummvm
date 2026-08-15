# Skill: Review Package.swift

Use this skill to validate a proposed or existing `Package.swift` before
committing, or to diagnose package resolution errors.

## Checklist

### Target membership
- [ ] Every `.swift` file under `Sources/` belongs to exactly one target.
- [ ] Every `.mm` / `.cpp` / `.c` file under `Sources/ScummVMiOS/`,
      `Sources/ScummVMmacOS/`, and `Sources/ScummVMtvOS/` belongs to its
      respective target.
- [ ] `Sources/ScummVMEngineOverrides/` files are compiled as part of
      `ScummVMEngine` (they live under `Sources/` which is the engine target root).
- [ ] No source file appears in two targets simultaneously.

### Exclusion paths
- [ ] All paths in `exclude:` are relative to the target's `path:` setting.
      For `ScummVMEngine` (path: `"Sources"`), exclusions start with
      `"scummvm/..."` or `"ScummVMEngineOverrides/..."` etc.
- [ ] Exclusion entries are exact directory or file paths — not glob patterns.
- [ ] Every exclusion for an override has the corresponding comment:
      `// Overridden in ScummVMEngineOverrides: <reason>`.
- [ ] No exclusion path refers to a file that no longer exists in the submodule.

### Frameworks
- [ ] Every name in `ScummVMEngine`'s `dependencies:` array has a matching
      `.binaryTarget` in the `targets:` list.
- [ ] Every `.binaryTarget` path points to an existing directory in `Frameworks/`.
- [ ] No framework is listed more than once.
- [ ] Platform-conditional dependencies use `.when(platforms: [...])` correctly.

### Platform conditions
- [ ] `ScummVM` target conditionally links iOS/tvOS vs macOS glue.
- [ ] tvOS-specific targets are not mixed into iOS conditions without intent.
- [ ] All platform version constraints match: iOS 17+, tvOS 17+, macOS 15+.

### Swift tools version
- [ ] First line is `// swift-tools-version:6.0`.
- [ ] No API used that requires a higher tools version.

### Validation command

Run this to catch structural errors before pushing:
```sh
swift package dump-package > /dev/null && echo "OK"
```

A successful parse does not guarantee a successful build, but it catches
malformed JSON/Swift syntax in the manifest.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Exclusion path missing leading target prefix | File compiled twice or not found | Prepend `scummvm/` to the path |
| Binary target name mismatch | `no such module` at link time | Align `.binaryTarget(name:)` with the dependency string |
| Glob in exclusion list | SPM ignores the entry silently | Use exact path |
| Stale exclusion after submodule update | Warning or phantom exclusion | Remove the entry |
| iOS-only xcframework linked for tvOS | Link error on tvOS slice | Add `.when(platforms:)` condition |
