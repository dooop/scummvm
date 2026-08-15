---
mode: agent
description: Create and maintain minimal override translation units for ScummVM wrapper compatibility. Use when an upstream source in scummvm/ cannot be built as-is and must be replaced by a file in swift/Sources/ScummVMEngineOverrides/ with a synchronized exclusion in Package.swift.
---

# ScummVM Override Workflow

Use this process when source replacement is unavoidable.

## Guardrails

- Treat override work as a last resort.
- Never edit `scummvm/` directly.
- Keep behavior aligned with upstream; change only what is required for platform/SPM compatibility.

## Workflow

1. Confirm a wrapper-only or `Package.swift`-only fix is not sufficient.
2. Identify the exact upstream path that must be replaced.
3. Create a mirrored override path under `swift/Sources/ScummVMEngineOverrides/`.
4. Copy the upstream file as baseline, then apply the smallest patch.
5. Add or confirm the upstream file path is excluded in `Package.swift`.
6. Ensure the override file is included by target source discovery and compiles once.
7. Rebuild on affected platforms.

## Patch Discipline

- Preserve function signatures and macro contracts unless the build failure requires change.
- Avoid formatting-only edits so future upstream rebases remain easy.
- Add a short comment only for non-obvious divergence from upstream.

## Verification

- Confirm no duplicate symbol errors.
- Confirm the failing symbol/path now resolves to the override translation unit.
- Record upstream path, override path, and reason in the change summary.
