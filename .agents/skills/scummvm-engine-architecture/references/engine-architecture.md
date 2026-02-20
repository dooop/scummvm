# Engine Architecture (Wrapper-Specific)

## Repository Boundaries

- `Sources/ScummVMEngine/` is upstream source (submodule): read-only for this project.
- Wrapper/edit surface:
- `Sources/ScummVM/` (SwiftUI API)
- `Sources/ScummVMiOS/` and `Sources/ScummVMmacOS/` (ObjC++ bridge)
- `Sources/ScummVMEngineOverrides/` (replacement translation units)
- `Package.swift` (build graph, flags, exclusions, resources)

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

## Engine Registration

- Plugin registration is controlled by generated-style tables included by upstream code paths.
- Wrapper overrides for tables live under `Sources/ScummVMEngineOverrides/engines/` when needed.

## Override Strategy

Use overrides only when build compatibility cannot be solved by wrapper or package configuration.

Required pair:

- exclude upstream file path in `Package.swift`
- provide replacement at mirrored path under `Sources/ScummVMEngineOverrides/`

## Change-Risk Hotspots

- Lifecycle/threading: start/stop reentrancy, main-thread UI/OSystem operations.
- Linkage: mismatched XCFramework slices, missing libs, wrong conditional dependencies.
- Resource lookup: theme/extra path arguments differ by iOS/tvOS vs macOS behavior.
- Plugin coverage: detection/plugin table drift after upstream sync.
