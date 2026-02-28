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
- Binary XCFramework zips are hosted in GitHub Releases and referenced as remote SwiftPM binary targets in `Package.swift`.
- [`Sources/ScummVMEngineOverrides/`](Sources/ScummVMEngineOverrides/) contains replacement translation units used when upstream sources need package-specific build fixes.

## Package targets (from `Package.swift`)
Source and executable targets:
- [`ScummVM`](Sources/ScummVM/)
- [`ScummVMApp`](Sources/ScummVMApp/)
- [`ScummVMEngine`](Sources/ScummVMEngine/) (with overrides in [`Sources/ScummVMEngineOverrides/`](Sources/ScummVMEngineOverrides/))
- [`ScummVMiOS`](Sources/ScummVMiOS/)
- [`ScummVMmacOS`](Sources/ScummVMmacOS/)
- [`ScummVMtvOS`](Sources/ScummVMtvOS/)

Binary targets (downloaded from the pinned GitHub Release configured in `Package.swift`, currently `0.2.0`):
- `a52`, `bz2`, `curl`, `faad`, `ffi`, `FLAC`, `fluidsynth`, `freetype`, `fribidi`, `gif`, `glib-2.0`, `intl`, `jpeg`, `mad`, `mikmod`, `mpeg2`, `ogg`, `png`, `SDL2_net`, `SDL2`, `theoradec`, `vorbis`, `vorbisfile`, `vpx`

Key entry points:
- `ScummVM` SwiftUI view manages start/stop lifecycle and initializes the shared engine instance.
- `ScummVMView` bridges the engine UI into SwiftUI (iOS/tvOS uses a `UIViewController`, macOS provides an empty host view while SDL owns its window).
- `ScummVMEngine` ObjC API is the minimal bridge used by Swift.

## Requirements
- Platforms: iOS 14+, tvOS 14+, macOS 12+.
- Swift tools version: 6.0 (see `Package.swift`).
- The `ScummVMEngine/` submodule must be initialized.
- Internet access is required on first package resolve/build so SwiftPM can download the XCFramework zips from the pinned GitHub Release (they are cached locally after download).
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9.20+ (declared as a Swift Package dependency in `Package.swift`).

## Setup
1. Initialize the submodule:
   ```sh
   git submodule update --init --recursive
   ```
2. Open the package in Xcode or add it as a Swift Package dependency.
3. Build for your desired platform target (iOS/tvOS/macOS). SwiftPM will download the XCFramework zip assets from the pinned GitHub Release on first resolve/build.

## Usage

### SwiftUI (recommended)
```swift
import ScummVM

struct ContentView: View {
	var body: some View {
		// No game path — opens the ScummVM launcher UI.
		ScummVM()
	}
}
```

Pass a game path URL to launch directly into a specific game:
```swift
import ScummVM

struct ContentView: View {
	// Points to a game directory or a .zip / .scummvm archive.
	let gameURL: URL

	var body: some View {
		ScummVM(gamePath: gameURL)
	}
}
```

Use a `Binding<URL?>` to change the game at runtime:
```swift
import ScummVM

struct ContentView: View {
	@State private var gameURL: URL? = nil

	var body: some View {
		ScummVM(gamePath: $gameURL)
		// Changing gameURL restarts the engine with the new path.
	}
}
```

`ScummVM` automatically calls `start()` on appear and `stop()` on disappear. The iOS/tvOS runtime ignores repeated `start()` calls while the engine is already running.

### Lower-level control
If you need manual control, you can use `ScummVMView` and call `ScummVMEngineSharedInstance().start(gamePath:)` / `stop()` yourself.

- iOS/tvOS: call `ScummVMEngineSharedInstance().ui()` to obtain the `UIViewController` backing the engine UI if you need to embed it manually.
- macOS: the SDL backend creates and manages its own window. The macOS `ScummVMEngine` API does not expose a `ui()` method; use the `ScummVM` SwiftUI view as the host.

## Runtime data and savegames
- iOS/tvOS savegames are created in the app's Documents directory under `Savegames/` at engine startup.
- macOS savegames are created in the Documents directory under `Savegames/` during engine setup.
- Wrapper-managed stop requests perform a best-effort autosave before engine shutdown.
- When a non-nil game path is used, startup passes `--save-slot` (native autosave slot) so ScummVM restores autosave when available.
- On macOS, explicit game-path launches first try to resolve an existing configured target and launch it directly with native `save_slot` restore; if no target matches, startup falls back to `--path` + `--auto-detect`. When game path is nil, launcher-only behavior is preserved and wrapper-owned save-slot hints are cleared.
- Theme and engine-data paths are resolved by scanning the app bundle; iOS/tvOS uses `appbundle:/` virtual paths and prefers `scummremastered.zip` when present, while macOS adds `--themepath`, `--iconspath`, and `--extrapath` with absolute bundle paths when needed.
- ScummVM configuration and game data files follow upstream behavior and are not customized here.

## Game path resolution and archive extraction
`ScummVMGamePathResolver` (an `actor` in `Sources/ScummVM/`) is responsible for resolving the `gamePath` URL into a concrete directory before the engine starts. Resolution is asynchronous and cancellation-aware.

### Archive extraction (all platforms)
- Supported archive extensions: `.zip`, `.scummvm`.
- Archives are extracted via ZIPFoundation to a platform-specific cache directory:
  - iOS/tvOS: `Documents/ScummVM/ImportedArchives/<name>-<hash>/`
  - macOS: `Application Support/ScummVM/ImportedArchives/<name>-<hash>/`
- The extraction is cached by a FNV1a-64 hash of the archive's full path. Re-extraction is skipped if the cached directory already exists and is non-empty.
- If the archive contains a single top-level subdirectory, the resolver descends into it automatically to locate the actual game root.

### Directory import (iOS/tvOS only)
- Game directories already within `Documents/` or the app bundle are used in place without copying.
- Directories outside those locations (e.g. received via the Files app or document picker) are copied to `Documents/ScummVM/ImportedDirectories/<name>-<hash>/`.
- macOS does not copy directories; the path is passed directly to the engine.

## Build notes and troubleshooting
- The engine target links against remote XCFramework binary targets from the pinned GitHub Release in `Package.swift`. If you see missing symbols, verify the uploaded XCFrameworks include the platform slice you are building for and that the checksums in `Package.swift` match the uploaded zip assets.
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
This wrapper is under active development. Current state:
- The `start`/`stop` lifecycle is fully implemented via a state machine in `ScummVMViewModel` with phases: `idle`, `resolvingPath`, `startRequested`, `stopRequested`.
- Game path resolution and archive extraction run asynchronously using Swift structured concurrency before the engine starts. Start tokens guard against races when the path changes mid-resolution.
- iOS/tvOS creates UIKit/backend state on the main thread, then runs the engine loop (`iOS7_init`) on a background queue.
- macOS sets up SDL/OSystem and runs `scummvm_main` on the main queue.
- Moving macOS engine execution to a background thread is a known next step; do not add main-thread assumptions that would block that migration.
- Cross-platform lifecycle/threading behavior is still evolving and not yet unified.
- Consider a macOS-specific SwiftUI host that can focus or resize the SDL window alongside the empty placeholder view.
- `ScummVMApp` is macOS-only; a tvOS/iOS equivalent app target may be useful for standalone testing.

## License
This wrapper follows the upstream ScummVM licensing. See the license files inside the `Sources/ScummVMEngine/` submodule for details.
