---
name: scummvm-submodule-sync
description: Update and reconcile the upstream ScummVM submodule for both platform wrappers. Use when advancing scummvm to a newer upstream commit, reviewing Swift override and Package.swift drift, or checking Android native-build, staged Java, assets, and NDK assumptions after upstream file churn.
---

# ScummVM Submodule Sync

Keep upstream syncs small, auditable, and compatible with wrapper constraints.

## Guardrails

- Never edit files under `scummvm/`.
- Update only the submodule pointer plus wrapper-side files (`Package.swift`, `swift/Sources/ScummVMEngineOverrides/`, `android/`, documentation) when required.
- Keep override diffs minimal against the new upstream file version.

## Workflow

1. Record the current upstream SHA with `git -C scummvm rev-parse HEAD`.
2. Advance `scummvm` to the requested upstream commit or branch.
3. Capture upstream file churn with `git -C scummvm diff --name-status <old-sha> HEAD`.
4. Reconcile overrides by mapping each file in `swift/Sources/ScummVMEngineOverrides/` to its upstream peer, then remove obsolete overrides or rebase still-needed overrides with minimal deltas.
5. Reconcile `Package.swift` exclusions by removing stale upstream paths and keeping one explicit exclusion for each active override replacement.
6. Reconcile Android `upstreamJavaSources`, runtime asset staging, native configure flags, and NDK assumptions against upstream changes.
7. Rebuild at least one affected Apple platform and the affected Android library path, then rerun any previously failing command.

## Verification

- Submodule pointer change is intentional and staged.
- No duplicate symbol regressions appear from stale include or exclusion pairs.
- Manifest parsing succeeds with `swift package dump-package > /dev/null`.

## Report Back

State old and new submodule SHAs, Swift override/exclusion changes, Android staging/build changes, and final platform build status.
