# Skill: Diagnose a build failure

Use this skill to triage a build failure before attempting any fix. Jumping to a
fix without classification leads to wrong or oversized changes.

## Step 1: Capture the exact error

Collect the full error text, including:
- File path and line number
- Error code (e.g. `error:`, `linker command failed`, `no such module`)
- Any notes or context lines that follow

## Step 2: Classify the error

| Class | Indicators | Typical fix |
|---|---|---|
| Missing header | `'Foo.h' file not found` | Add search path flag in `Package.swift` |
| Excluded file needed | Source file cannot be found at link time | Remove wrong exclusion from `Package.swift` |
| Excluded file conflict | Duplicate symbol or ODR violation | Add exclusion for the conflicting file |
| Compiler flag missing | Feature macro not defined, C++ standard mismatch | Add `-D` or `-std=` flag to `cxxSettings`/`cSettings` |
| Swift/ObjC++ interop | `cannot find type`, `use of undeclared identifier` in bridging | Fix or add a header in the relevant `include/` directory |
| Linker error | `Undefined symbol`, `framework not found` | Add missing xcframework or dependency to target |
| Concurrency/Swift 6 | `Sendable`, `actor isolation` errors | Fix in glue code only; do not change upstream |
| Upstream source bug | Error inside `ScummVMEngine/` that cannot be fixed by flags | Use the `create-engine-override` skill |

## Step 3: Apply the fix in order of preference

1. `Package.swift` only (flag, exclusion, path) — no source change.
2. Glue code change (`Sources/ScummVMiOS/`, `Sources/ScummVMmacOS/`,
   `Sources/ScummVMtvOS/`, or `Sources/ScummVM/`).
3. Engine override — use the `create-engine-override` skill.

Never skip to step 3 without first confirming steps 1 and 2 cannot resolve the
error.

## Step 4: Verify the fix is scoped correctly

- The fix touches only files in the allowed edit surface (see copilot-instructions).
- No file under `ScummVMEngine/` has been modified.
- The same error does not reappear on a clean build.

## Output format when reporting a diagnosis

```
Error class: <class from table>
File: <path>:<line>
Root cause: <one sentence>
Proposed fix: <location and nature of change>
```
