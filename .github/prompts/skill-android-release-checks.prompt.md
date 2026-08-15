---
mode: agent
description: Audit and validate ScummVM Android release outputs. Use before publishing or consuming the Android AAR, when changing packaging, assets, ABIs, ProGuard rules, manifests, CI artifacts, or when verifying the release sample app against a produced AAR.
---

# Android Release Checks

Validate the library artifact as a consumer receives it, not only the local project dependency.

## Workflow

1. Build the release AAR with `./gradlew :scummvm:assembleRelease` using the intended ABIs and engine configuration.
2. Inspect the AAR contents and require, for every selected ABI:
   - `libscummvm.so`
   - `liboboe.so`
   - `libc++_shared.so`
3. Confirm staged runtime data, upstream JNI Java classes, wrapper classes, consumer rules, and the neutral library manifest are present.
4. Check each native library architecture and 16 KB load-segment alignment with platform tooling.
5. Build the release sample app against the produced AAR using `-Pscummvm.releaseAar=<absolute-path>`.
6. Inspect the APK for the expected ABI libraries and ensure no unintended ABI or duplicate native runtime is packaged.
7. Compare CI cache inputs and uploaded artifact paths when packaging inputs change.

## Guardrails

- Never validate only `:app`'s debug project dependency when the deliverable is an AAR.
- Never modify generated artifacts to make a check pass; fix their declared inputs.
- Keep the upstream submodule read-only and record its SHA for release traceability.
- Treat missing runtime data as a release-blocking failure even when compilation succeeds.

## Report Back

List the AAR and APK checked, ABIs found, required libraries/assets verified, consumer build result, and any release blockers.
