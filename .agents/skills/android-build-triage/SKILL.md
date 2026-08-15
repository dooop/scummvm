---
name: android-build-triage
description: Diagnose and resolve Android build failures in the ScummVM wrapper. Use when Gradle, AGP, Kotlin, Compose, Java staging, upstream configure/make, NDK linking, JNI packaging, AAR assembly, or the Android sample app fails.
---

# Android Build Triage

Find the first actionable failure and fix it at the narrowest downstream layer.

## Guardrails

- Never edit `scummvm/` or generated files under `android/**/build/`.
- Do not replace upstream `configure` and `make` with a parallel CMake or ndk-build graph.
- Keep NDK r28 or newer and 16 KB page compatibility intact.
- Preserve upstream Java staging; do not check copied upstream Java into the wrapper.

## Workflow

1. Re-run the exact failing Gradle task with `--stacktrace`; add `--info` only when task output is insufficient.
2. Classify the first failure:
   - Gradle configuration, plugin, or dependency resolution
   - Kotlin, Compose, or Java compilation
   - missing Android SDK or NDK toolchain
   - upstream `configure` or `make`
   - native link, ABI, or JNI packaging
   - AAR consumer/sample app integration
3. Inspect the task inputs and generated output under `android/scummvm/build/` without editing generated files.
4. Prefer fixes in `android/scummvm/build.gradle.kts`, root Gradle configuration, or wrapper Kotlin/Java sources.
5. Use `-Pscummvm.prebuiltLibsDir=<dir>` only when intentionally isolating Kotlin/AAR work from native compilation.
6. Re-run the original task and one adjacent packaging or consumer task.

## Useful Checks

- `./gradlew :scummvm:tasks --all`
- `./gradlew :scummvm:assembleDebug --stacktrace`
- `./gradlew :app:assembleDebug --stacktrace`
- `unzip -l android/scummvm/build/outputs/aar/scummvm-*.aar`
- `readelf -l <libscummvm.so>` and `file <libscummvm.so>` for ABI/page alignment issues

## Report Back

State the failing task, root cause, changed downstream files, toolchain versions involved, and verification tasks.
