# Engine Architecture (Wrapper-Specific)

## Repository Boundaries

- `scummvm/` is upstream source (submodule): read-only for this project.
- Wrapper/edit surface:
- `swift/Sources/ScummVM/` (SwiftUI API)
- `swift/Sources/ScummVMiOS/` and `swift/Sources/ScummVMmacOS/` (ObjC++ bridge)
- `swift/Sources/ScummVMEngineOverrides/` (replacement translation units)
- `Package.swift` (build graph, flags, exclusions, resources)
- `android/scummvm/` (Compose library, JNI host, Gradle native build and packaging)
- `android/app/` (sample application and release-AAR consumer validation)

## Runtime Layers

1. SwiftUI layer
- `ScummVM` triggers `start()` on appear and `stop()` on disappear.
- `ScummVMView` hosts a UIKit controller on iOS/tvOS; macOS uses an empty host view while SDL manages its own window.

2. Objective-C++ engine facade
- `ScummVMEngineSharedInstance()` provides singleton bridge.
- Public bridge surface remains intentionally small (`start`, `stop`, `ui` on iOS/tvOS).

3. Platform app context
- iOS/tvOS: `ScummVMAppContext` sets up iOS backend view/controller, builds OSystem, then runs `scummvm_main` through `iOS7_init`.
- macOS: `ScummVMAppContext` initializes `OSystem_MacOSX` and runs `scummvm_main` on main queue with runtime arguments.

4. Engine + resources
- `Package.swift` target `ScummVMEngine` defines engine dependencies, compile flags, source exclusions, and copied runtime payloads (themes, engine-data, soundfonts, networking assets).

5. Android Compose + JNI host
- `org.scummvm.ScummVM` owns the Compose lifecycle and delegates to `ScummVMEngine`.
- `ScummVMHost` preserves the upstream JNI package contract in `org.scummvm.scummvm`.
- Gradle invokes upstream `configure` and `make` out-of-tree, stages selected upstream Java and runtime assets, and packages native dependencies in the AAR.
- The sample app consumes the local project in debug and the produced AAR in release.

## Engine Registration

- Plugin registration is controlled by generated-style tables included by upstream code paths.
- Wrapper overrides for tables live under `swift/Sources/ScummVMEngineOverrides/engines/` when needed.

## Override Strategy

Use overrides only when build compatibility cannot be solved by wrapper or package configuration.

Required pair:

- exclude upstream file path in `Package.swift`
- provide replacement at mirrored path under `swift/Sources/ScummVMEngineOverrides/`

## Change-Risk Hotspots

- Lifecycle/threading: start/stop reentrancy, main-thread UI/OSystem operations.
- Linkage: mismatched XCFramework slices, missing libs, wrong conditional dependencies.
- Resource lookup: theme/extra path arguments differ by iOS/tvOS vs macOS behavior.
- Plugin coverage: detection/plugin table drift after upstream sync.
- Android packaging: JNI class-name drift, missing staged assets, ABI gaps, or duplicate native runtimes.
