# Copilot instructions

## Project goal

- Provide thin Apple and Android wrappers around upstream ScummVM.
- Reuse the shared C/C++ engine through the `scummvm/` git submodule.
- Keep platform code isolated in `swift/` and `android/` and keep upstream read-only.

## Structure map

- `Package.swift`: root SwiftPM entry point; Swift targets map explicitly into `swift/`.
- `swift/`: SwiftUI sources, Objective-C++ glue, tests, framework staging, release scripts, and Swift documentation.
- `android/`: Jetpack Compose library and sample app; root Gradle files configure both modules.
- `scummvm/`: upstream ScummVM submodule shared by Swift source mode and Android; never edit.
- `swift/Sources/ScummVMEngine`: read-only symlink to `../../scummvm` for SwiftPM target scoping.
- `.agents/skills/`: focused Apple, Android, packaging, and submodule workflows.

## Non-negotiable rules

- Never modify, delete, reformat, or fix files under `scummvm/` or through `swift/Sources/ScummVMEngine`.
- Keep changes in platform wrappers, root build configuration, documentation, CI, or agent workflows.
- For unavoidable Swift source incompatibilities, add a minimal mirrored override under `swift/Sources/ScummVMEngineOverrides/` and exclude its upstream peer in `Package.swift`.
- For Android, consume upstream Java through Gradle staging and upstream native code through `configure`/`make`; do not check in copied upstream Java or create a parallel engine build graph.
- Do not add public wrapper API without explicit user direction.

## Platform boundaries

### Swift

- Sources: `swift/Sources/`
- Tests: `swift/Tests/`
- XCFramework tooling: `swift/Scripts/`
- Documentation: `swift/README.md`
- Default build mode uses remote engine XCFrameworks. Set `SCUMMVM_BUILD_FROM_SOURCE=1` for engine, override, glue, or build-flag changes and run `swift package reset` when switching modes.
- Supported: iOS 17+, tvOS 17+, macOS 15+, arm64 only.

### Android

- Library: `android/scummvm/`
- Sample app: `android/app/`
- Root configuration: `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`, `gradle/`, `gradlew`
- Documentation: `android/README.md`
- Build with JDK 17+, Android SDK, and NDK r28 or newer; the repository default is declared in `gradle.properties`.
- Preserve `org.scummvm.scummvm` for JNI compatibility and the one-engine-host-per-process lifecycle.

## Skills

- `scummvm-build-triage`: Swift compile, link, header, macro, or target failures.
- `scummvm-override-workflow`: Swift engine override and exclusion pairs.
- `objcxx-bridge-lifecycle`: SwiftUI/Objective-C++ lifecycle and threading.
- `plugins-table-maintainer`: Swift plugin and detection table overrides.
- `xcframework-linkage-check`: Apple XCFramework slices and linkage.
- `package-swift-auditor`: `Package.swift` targets, paths, exclusions, and dependencies.
- `android-compose-development`: Compose API, JNI host, input, archive import, and lifecycle changes.
- `android-build-triage`: Gradle, Kotlin, NDK, native build, JNI, AAR, or sample failures.
- `android-release-checks`: AAR/APK contents, ABIs, assets, and consumer validation.
- `scummvm-engine-architecture`: cross-platform wrapper-to-engine architecture and change impact.
- `scummvm-submodule-sync`: upstream updates plus Swift and Android drift checks.

Open and apply the matching skill whenever the task description triggers it.

## Build issue policy

- Capture the exact command and first actionable error.
- Fix the narrowest downstream layer: platform wrapper, build configuration, then a Swift override only if unavoidable.
- Never edit generated files under `.build/`, `build/`, or `android/**/build/` as the source fix.
- Verify the original failing task and an adjacent package or consumer task.

## Documentation and output

- Keep `README.md` as the cross-platform overview.
- Keep platform detail in `swift/README.md` and `android/README.md`.
- For reviews, list findings first, ordered by severity, with file links.
- Default to ASCII and keep comments minimal and focused.
