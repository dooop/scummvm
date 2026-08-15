# ScummVM

Thin native wrappers around the upstream [ScummVM](https://github.com/scummvm/scummvm) engine for Apple and Android applications. The repository shares one read-only `scummvm/` submodule while keeping each platform wrapper isolated.

## Repository layout

```text
.
├── Package.swift          SwiftPM entry point
├── swift/                 SwiftUI, Objective-C++, tests, and XCFramework tooling
├── android/               Jetpack Compose library and sample application
├── scummvm/               upstream ScummVM submodule (read-only)
├── gradle/                shared Android Gradle wrapper and version catalog
└── .agents/               repository development workflows and checks
```

Platform documentation:

- [Swift package](swift/README.md) — iOS 17+, tvOS 17+, and macOS 15+ integration, source/binary build modes, lifecycle, testing, and engine releases.
- [Android](android/README.md) — Compose API, AAR integration, native NDK build, sample app, release validation, and known limitations.

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

See the platform README before changing engine integration or publishing artifacts. Swift source, tests, and packaging scripts live under `swift/`; only the consumer-facing `Package.swift` stays at the repository root.

## Development rules

- Never edit `scummvm/` or `swift/Sources/ScummVMEngine`; both expose upstream source.
- Keep platform changes inside `swift/`, `android/`, or root build configuration.
- Put Swift-only upstream compatibility changes in `swift/Sources/ScummVMEngineOverrides/` and pair them with an exclusion in `Package.swift`.
- Keep public wrapper APIs small and stable unless a change is explicitly requested.
- Update the relevant platform README and agent workflow when build or lifecycle behavior changes.

## License

The wrappers follow the upstream ScummVM licensing. See the license files in the `scummvm/` submodule for engine-specific terms.
