# swift-scummvm

SwiftUI wrapper around the upstream ScummVM codebase, packaged as a Swift Package with minimal ObjC++ glue. The core goal is to reuse as much upstream C/C++ as possible while keeping platform-specific wrapper code small and focused.

Upstream ScummVM repository: [scummvm/scummvm](https://github.com/scummvm/scummvm).

## Goals
- Reuse upstream ScummVM code directly via the `Sources/ScummVMEngine/` git submodule.
- Keep Swift and ObjC++ wrappers thin and localized to `Sources/`.
- Avoid long-lived forks or large downstream patches in the submodule.
- Ship as a Swift Package that can be embedded in iOS, tvOS, and macOS apps.

## Architecture
- [`ScummVM`](Sources/ScummVM/) (SwiftUI target) exposes the public Swift UI.
- [`ScummVMEngine`](Sources/ScummVMEngine/) (C/C++ target) wraps the upstream submodule and build flags.
- [`ScummVMiOS`](Sources/ScummVMiOS/) and [`ScummVMmacOS`](Sources/ScummVMmacOS/) (ObjC++ targets) provide platform glue.
- [`ScummVMtvOS`](Sources/ScummVMtvOS/) (Swift target) re-exports `ScummVMiOS` via `@_exported import` and packages tvOS-specific assets (app icons, privacy manifest).
- [`ScummVMApp`](Sources/ScummVMApp/) (macOS executable target) is a minimal macOS app for development and testing that embeds `ScummVM`.
- [`Frameworks/`](Frameworks/) contains prebuilt XCFrameworks used by the engine target.
- [`Sources/ScummVMEngineOverrides/`](Sources/ScummVMEngineOverrides/) contains replacement translation units used when upstream sources need package-specific build fixes.

## Package targets (from `Package.swift`)
Source and executable targets:
- [`ScummVM`](Sources/ScummVM/)
- [`ScummVMApp`](Sources/ScummVMApp/)
- [`ScummVMEngine`](Sources/ScummVMEngine/) (with overrides in [`Sources/ScummVMEngineOverrides/`](Sources/ScummVMEngineOverrides/))
- [`ScummVMiOS`](Sources/ScummVMiOS/)
- [`ScummVMmacOS`](Sources/ScummVMmacOS/)
- [`ScummVMtvOS`](Sources/ScummVMtvOS/)

Binary targets:
- [`a52`](Frameworks/a52.xcframework), [`bz2`](Frameworks/bz2.xcframework), [`curl`](Frameworks/curl.xcframework), [`faad`](Frameworks/faad.xcframework), [`ffi`](Frameworks/ffi.xcframework), [`FLAC`](Frameworks/FLAC.xcframework), [`fluidsynth`](Frameworks/fluidsynth.xcframework), [`freetype`](Frameworks/freetype.xcframework), [`fribidi`](Frameworks/fribidi.xcframework), [`gif`](Frameworks/gif.xcframework), [`glib-2.0`](Frameworks/glib-2.0.xcframework), [`intl`](Frameworks/intl.xcframework), [`jpeg`](Frameworks/jpeg.xcframework), [`mad`](Frameworks/mad.xcframework), [`mikmod`](Frameworks/mikmod.xcframework), [`mpeg2`](Frameworks/mpeg2.xcframework), [`ogg`](Frameworks/ogg.xcframework), [`png`](Frameworks/png.xcframework), [`SDL2_net`](Frameworks/SDL2_net.xcframework), [`SDL2`](Frameworks/SDL2.xcframework), [`theoradec`](Frameworks/theoradec.xcframework), [`vorbis`](Frameworks/vorbis.xcframework), [`vorbisfile`](Frameworks/vorbisfile.xcframework), [`vpx`](Frameworks/vpx.xcframework)

Key entry points:
- `ScummVM` SwiftUI view manages start/stop lifecycle and initializes the shared engine instance.
- `ScummVMView` bridges the engine UI into SwiftUI (iOS/tvOS uses a `UIViewController`, macOS provides an empty host view while SDL owns its window).
- `ScummVMEngine` ObjC API is the minimal bridge used by Swift.

## Requirements
- Platforms: iOS 14+, tvOS 14+, macOS 12+.
- Swift tools version: 6.0 (see `Package.swift`).
- The `ScummVMEngine/` submodule must be initialized.
- The XCFrameworks under `Frameworks/` must be present and match your target platform.

## Setup
1. Initialize the submodule:
   ```sh
   git submodule update --init --recursive
   ```
2. Open the package in Xcode or add it as a Swift Package dependency.
3. Build for your desired platform target (iOS/tvOS/macOS).

## Usage

### SwiftUI (recommended)
```swift
import ScummVM

struct ContentView: View {
	var body: some View {
		ScummVM()
	}
}
```

`ScummVM` automatically calls `start()` on appear and `stop()` on disappear. The iOS/tvOS runtime ignores repeated `start()` calls while the engine is already running.

### Lower-level control
If you need manual control, you can use `ScummVMView` and call `ScummVMEngineSharedInstance().start()` / `stop()` yourself.

- iOS/tvOS: call `ScummVMEngineSharedInstance().ui()` to obtain the `UIViewController` backing the engine UI if you need to embed it manually.
- macOS: the SDL backend creates and manages its own window. The macOS `ScummVMEngine` API does not expose a `ui()` method; use the `ScummVM` SwiftUI view as the host.

## Runtime data and savegames
- iOS/tvOS savegames are created in the app's Documents directory under `Savegames/` at engine startup.
- macOS savegames are created in the Documents directory under `Savegames/` during engine setup.
- Theme and engine-data paths are resolved by scanning the app bundle; iOS/tvOS uses `appbundle:/` virtual paths and prefers `scummremastered.zip` when present, while macOS adds `--themepath`, `--iconspath`, and `--extrapath` with absolute bundle paths when needed.
- ScummVM configuration and game data files follow upstream behavior and are not customized here.

## Build notes and troubleshooting
- The engine target links against the XCFrameworks in `Frameworks/`. If you see missing symbols, verify the XCFrameworks include the platform slice you are building for.
- iOS/tvOS uses the upstream iOS7 backend; macOS uses the SDL backend.
- `ScummVMtvOS` is a thin Swift re-export of `ScummVMiOS` (`@_exported import ScummVMiOS`) that packages tvOS-specific resources from `ScummVMEngine/dists/tvos` (app icons and privacy manifest). It has no separate ObjC++ glue of its own.
- `ScummVMEngine` sources are taken from the upstream submodule (`ScummVMEngine/`).
- Override-only files live in `Sources/ScummVMEngineOverrides/` (plus platform glue in `Sources/ScummVMiOS/` and `Sources/ScummVMmacOS/`).
- If a submodule source file causes an SPM-only issue, exclude it in `Package.swift` and add a replacement translation unit under `Sources/ScummVMEngineOverrides/`.
- Run `.github/scripts/check-override-hygiene.sh` to validate override/exclusion consistency before opening a PR.

## Quick start (read before making changes)
- Never modify anything under `Sources/ScummVMEngine/`. It is a git submodule of upstream ScummVM and must remain untouched.
- Allowed edit surface: `Sources/ScummVM/`, `Sources/ScummVMiOS/`, `Sources/ScummVMmacOS/`, `Sources/ScummVMEngineOverrides/`, `Package.swift`, `README.md`.
- If a build issue needs source changes, add a replacement file in `Sources/ScummVMEngineOverrides/` and exclude the upstream file in `Package.swift`.
- Keep public API small and stable: `ScummVM`, `ScummVMView`, `ScummVMEngine`.
- Capture exact build errors before proposing fixes; prefer minimal wrapper or build-flag changes.

## Status and next steps
This wrapper is under active development. Known gaps and suggested next steps:
- The `start`/`stop` lifecycle is wired up in SwiftUI with run-state guards in ObjC++.
- iOS/tvOS currently creates UIKit/backend state on the main thread, then runs the engine loop (`iOS7_init`) on a background queue.
- macOS currently sets up SDL/OSystem and runs `scummvm_main` on the main queue.
- Cross-platform lifecycle/threading behavior is still evolving and not yet unified.
- Consider a macOS-specific SwiftUI host that can focus or resize the SDL window alongside the empty placeholder view.
- `ScummVMApp` is macOS-only; a tvOS/iOS equivalent app target may be useful for standalone testing.

## License
This wrapper follows the upstream ScummVM licensing. See the license files inside the `Sources/ScummVMEngine/` submodule for details.
