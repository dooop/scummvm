---
name: android-compose-development
description: Develop and review the ScummVM Android Jetpack Compose wrapper, public Kotlin API, JNI-facing host, input handling, archive import, and lifecycle behavior. Use when changing files under android/app or android/scummvm, especially ScummVM, ScummVMView, ScummVMEngine, ScummVMConfiguration, ScummVMHost, or internal Android glue.
---

# Android Compose Development

Keep the Compose API, Android lifecycle, and native ScummVM singleton coherent.

## Guardrails

- Never modify `scummvm/`; consume upstream native and Java sources through the Gradle staging tasks.
- Keep the public API small and stable unless expansion is explicitly requested.
- Preserve the exact `org.scummvm.scummvm` package for JNI compatibility classes.
- Keep engine work off the UI thread and Compose state updates lifecycle-aware.
- Assume one native engine host per process.

## Workflow

1. Trace the affected path from `ScummVM` or `ScummVMView` through `ScummVMEngine`, internal helpers, and `ScummVMHost`.
2. Identify ownership of the engine, surface, coroutine scope, callbacks, and Android context before editing.
3. Make the smallest wrapper-side change in `android/scummvm/src/main/` or the sample change in `android/app/src/main/`.
4. Preserve cancellation and disposal behavior for engine start, archive extraction, and surface teardown.
5. Verify touch, keyboard, controller, TV focus, and configuration-change implications when input or hosting changes.
6. Run focused Kotlin tests or compilation, then `./gradlew :scummvm:assembleDebug` or the nearest affected task.

## Review Checks

- No Activity or short-lived Context is retained beyond its lifecycle.
- No second native singleton can be constructed during recomposition or navigation.
- JNI callbacks retain their required class and method names.
- Blocking archive, asset, or native work does not run on the main dispatcher.
- The library manifest remains consumer-neutral unless a manifest change is explicitly required.

## Report Back

State the lifecycle path changed, public API impact, JNI impact, and Gradle checks run.
