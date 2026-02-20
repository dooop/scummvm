---
mode: agent
description: Provide architecture-level orientation for how the Swift wrapper hosts ScummVM. Use when planning or reviewing changes that touch engine startup, platform backends, plugin registration, runtime resources, or wrapper boundaries.
---

# ScummVM Engine Architecture

Use this skill to reason about change impact before patching.

## Read First

- See `skills/scummvm-engine-architecture/references/engine-architecture.md` for repository-specific architecture and call flow.

## Workflow

1. Identify requested change scope:
   - SwiftUI wrapper surface
   - Objective-C++ platform bridge
   - ScummVM engine configuration
   - override translation unit
2. Trace startup and teardown path for the affected platform.
3. Confirm whether change belongs in wrapper/glue, `Package.swift`, or override layer.
4. Enforce repository boundary: never patch upstream submodule sources.
5. Document risk to lifecycle, plugin registration, and runtime resource lookup.

## Decision Rules

- If issue is configuration/path/linking: prefer `Package.swift` or platform glue.
- If issue is compile incompatibility in upstream TU: add override plus exclusion.
- If issue is public API behavior: preserve existing API unless explicitly requested.

## Output

Return a short architecture-impact summary before implementing substantial edits.
