# ScummVM

Thin native wrappers around the upstream [ScummVM](https://github.com/scummvm/scummvm) engine for Apple and Android applications. The repository shares one read-only `scummvm/` submodule while keeping each platform wrapper isolated.

## Repository layout

```text
.
├── Package.swift          SwiftPM entry point
├── swift/                 SwiftUI, Objective-C++, tests, and XCFramework tooling
├── android/               Jetpack Compose library and sample application
├── scripts/               Apple and Android build, packaging, and validation utilities
├── scummvm/               upstream ScummVM submodule (read-only)
├── gradle/                shared Android Gradle wrapper and version catalog
└── .agents/               repository development workflows and checks
```

Platform documentation:

- [Swift package](swift/README.md) — iOS 17+, tvOS 17+, and macOS 15+ integration, source/binary build modes, lifecycle, testing, and engine releases.
- [Android](android/README.md) — Compose API, GitHub Packages Maven/AAR integration, native NDK build, sample app, release workflow, validation, and known limitations.

## Quick start

Initialize the upstream engine when working on source or Android builds:

```sh
git submodule update --init --recursive
```

Build and test the default Swift package configuration:

```sh
swift build
swift test
```

Build the Android library:

```sh
./gradlew :scummvm:assembleRelease
```

See the platform README before changing engine integration or publishing artifacts. Platform source and tests live under `swift/` and `android/`; repository utilities are centralized under `scripts/`.

## Formatting & linting

Swift wrapper code is formatted with the `swift-format` tool bundled in the Swift 6 toolchain, configured by `.swift-format`:

```sh
swift format lint --recursive --strict swift/Sources swift/Tests Package.swift
swift format format --in-place --recursive swift/Sources swift/Tests Package.swift
```

Kotlin code is linted with [ktlint](https://github.com/ktlint/ktlint) via the `org.jlleitschuh.gradle.ktlint` Gradle plugin:

```sh
./gradlew ktlintCheck
./gradlew ktlintFormat
```

Both run in CI (`lint-swift`, `lint-kotlin` jobs in `.github/workflows/ci.yml`).

## Development rules

- Never edit `scummvm/` or `swift/Sources/ScummVMEngine`; both expose upstream source.
- Keep platform changes inside `swift/`, `android/`, or root build configuration.
- Put Swift-only upstream compatibility changes in `swift/Sources/ScummVMEngineOverrides/` and pair them with an exclusion in `Package.swift`.
- Keep public wrapper APIs small and stable unless a change is explicitly requested.
- Update the relevant platform README and agent workflow when build or lifecycle behavior changes.

## License

The wrappers follow the upstream ScummVM licensing. See the license files in the `scummvm/` submodule for engine-specific terms.
