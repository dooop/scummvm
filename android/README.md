# ScummVM Android package

A Gradle build that packages the upstream ScummVM engine as an Android library
(`.aar`) with a Jetpack Compose view on top. It is the Android platform package
in the `scummvm` repository and follows the shared rule: the engine comes from
the root `scummvm` git submodule and is never modified.

```
./
├── settings.gradle.kts          ← root Android Studio project
├── gradle/                      ← version catalog and wrapper
├── gradlew
├── scummvm/                     ← upstream engine submodule
└── android/
    ├── app/                     ← Compose test app, produces the APK
    │   ├── build.gradle.kts     ← debug/local and release/AAR selection
    │   ├── libs/                ← default location for an uploaded AAR
    │   └── src/main/kotlin/org/scummvm/
    └── scummvm/                 ← the library module, produces the AAR
        ├── build.gradle.kts     ← native build + asset staging + packaging
        ├── consumer-rules.pro
        └── src/main/
            ├── java/org/scummvm/scummvm/  ← upstream declaration shim
            └── kotlin/
                ├── org/scummvm/           ← public Compose API
                └── org/scummvm/scummvm/   ← upstream-package glue
```

The library namespace, public Compose API, application ID, and Activity package
are `org.scummvm`. The test app uses `org.scummvm.app` only for its
generated-code namespace because Android Gradle rejects an app and a consumed
AAR with identical namespaces. The JNI compatibility classes must remain in
`org.scummvm.scummvm`: upstream's native backend looks them up by that exact
binary name, including when a prebuilt `libscummvm.so` is used.

## Usage

```kotlin
import org.scummvm.ScummVM
import org.scummvm.ScummVMConfiguration

setContent {
    ScummVM(
        modifier = Modifier.fillMaxSize(),
        configuration = ScummVMConfiguration(
            // null opens ScummVM's own launcher
            target = null,
            gamesDirectory = File(filesDir, "games"),
            // Optional content:// URI for a .zip or .scummvm document.
            gameUri = selectedDocumentUri,
        ),
        onExit = { exitCode -> finish() },
    )
}
```

Public API surface, intentionally small and mirroring the Swift package's
`ScummVM` / `ScummVMView` / `ScummVMEngine` split:

| Type | Role |
|---|---|
| `ScummVM` | Composable. Starts the engine on appear, stops it on dispose. |
| `ScummVMView` | Composable. Just hosts the surface and forwards input; you drive the lifecycle. |
| `ScummVMEngine` | The engine facade: `state`, `currentGame`, `importGame`, `setPaused`, `setTouchMode`, `stop`. |
| `ScummVMConfiguration` | Start-up options (target, game archive URI, games directory, extra arguments). |
| `ScummVMState` | `Idle` / `PreparingData` / `Running` / `Stopped` / `Failed`. |
| `ScummVMTouchMode` | `Touchpad` / `DirectMouse` / `Gamepad`. |

### What the consuming app must declare

The library manifest is deliberately empty — it merges nothing into your app.
Add what you actually need:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-feature android:name="android.hardware.opengles.aep" android:required="false" />
```

`INTERNET` is only needed for ScummVM's cloud sync and its built-in web server;
without `ACCESS_NETWORK_STATE` the engine conservatively assumes a metered
connection. The Activity hosting `ScummVM` should be
`android:configChanges="orientation|screenSize|keyboardHidden"` so the engine is
not torn down on rotation, and `android:hardwareAccelerated="true"`.

## Building

Prerequisites:

* JDK 17 or newer.
* Android SDK, with `sdk.dir` in `local.properties` or `ANDROID_SDK_ROOT`
  exported.
* **NDK 29.0.14206865 by default (r28 or newer is required).** These revisions
  build 16 KB-compatible ELF libraries and provide a compatible
  `libc++_shared.so`. Upstream's standalone Android project still pins r23; the
  wrapper generates a build-local copy of `configure` that relaxes only that
  exact-version check. The submodule remains untouched.

  ```sh
  "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" "ndk;29.0.14206865"
  ```

* The submodule: `git submodule update --init --recursive`.

Then:

```bash
./gradlew :scummvm:assembleRelease
```

The AAR lands in `android/scummvm/build/outputs/aar/`.

### Test app build modes

The `:app` module opens ScummVM's launcher in a full-screen Compose host. Its
engine dependency follows the Android build type:

| App build | Engine dependency |
|---|---|
| `debug` | Local `:scummvm` project, including the local native engine build |
| `release` | Prebuilt AAR, so the app can test an artifact downloaded from CI or a release |

Build and install the local debug version:

```bash
./gradlew :app:installDebug
```

For release, copy an uploaded artifact to `app/libs/scummvm-release.aar` and
build normally:

```bash
./gradlew :app:assembleRelease
```

The artifact can also remain anywhere on disk:

```bash
./gradlew :app:assembleRelease \
  -Pscummvm.releaseAar=/absolute/path/to/scummvm-release.aar
```

Release builds fail early with a focused message when the AAR is missing. A
flat AAR has no dependency metadata, so the app declares the wrapper's AndroidX,
Compose, and coroutine runtime dependencies itself.

### Android TV sample support

The sample app is available to both handheld and Android TV devices. Its host
manifest declares Leanback support, makes touchscreen/fake-touch optional, adds
the `LEANBACK_LAUNCHER` category, and supplies the required TV banner and app
icon. The same `ScummVMView` is used on both device classes: it requests focus
when attached and forwards D-pad, remote-select, gamepad buttons, sticks, hats,
and triggers to the native Android backend.

The sample intentionally relies on the platform's default demo launcher
artwork and does not ship custom icon or banner assets.

The sample does not require a touchscreen, but pointer remotes remain enabled.
Games that need more buttons than a basic D-pad remote provides should be used
with an Android-compatible game controller. Game import still uses Android's
Storage Access Framework; availability and TV usability of a document provider
depends on the device firmware.

### Importing `.scummvm` game archives

Pass a document URI returned by `ActivityResultContracts.OpenDocument()` as
`ScummVMConfiguration(gameUri = uri)`. Both `.scummvm` and `.zip` are treated as
ZIP containers, extracted off the UI thread into
`<filesDir>/ScummVM/Games`, and added recursively to ScummVM's library before
the launcher opens. The extractor rejects path traversal and ignores the macOS
`__MACOSX` folder. The sample app also accepts these files through Android's
**Open with** and **Share** actions. It uses a single Activity instance, so an
archive opened while ScummVM is already running is imported by the existing
engine instead of constructing a second native singleton.

```kotlin
val picker = rememberLauncherForActivityResult(
    ActivityResultContracts.OpenDocument(),
) { uri -> /* show ScummVM with ScummVMConfiguration(gameUri = uri) */ }

picker.launch(arrayOf("application/zip", "application/octet-stream"))
```

For a picker shown while the engine is already running, keep the remembered
engine and pass the result to `engine.importGame(uri)`.

### How the native build works

There is no CMake or `ndk-build` reimplementation of ScummVM here. Rebuilding
its hand-rolled `configure` in Gradle would be a large, permanently drifting
fork of upstream's build system. Instead, per ABI, Gradle runs upstream's own
build out-of-tree — exactly what `backends/platform/android/fatbundle.mk` does:

```
configureScummVM<Abi>   →  <submodule>/configure --host=android-<abi> …
buildScummVM<Abi>       →  make -j libscummvm.so
stageScummVMJniLibs     →  jni/<abi>/libscummvm.so
```

The same staging task also packages Oboe's `liboboe.so` and the NDK's
`libc++_shared.so` for each selected ABI. ScummVM links to Oboe dynamically, and
Oboe links to the shared C++ runtime, so all three libraries must be present in
the AAR and final APK.

`make` is left to decide what is stale, so the build task never reports
up-to-date; use the prebuilt escape hatch below when iterating on Kotlin.

### Build properties

Set in `gradle.properties` or on the command line with `-P`.

| Property | Default | Meaning |
|---|---|---|
| `scummvm.ndkVersion` | `29.0.14206865` | NDK used for the engine and packaged C++ runtime. Must be r28 or newer. |
| `scummvm.abis` | `arm64-v8a,x86_64` | Comma-separated ABIs. `armeabi-v7a` and `x86` additionally need the NDK cpufeatures sources. |
| `scummvm.configureArgs` | *(empty)* | Extra `./configure` flags, e.g. `--disable-all-engines --enable-engine=scumm,sky`. Empty means every stable engine — a long build. |
| `scummvm.buildJobs` | *(CPU count)* | `make -j` parallelism. |
| `scummvm.prebuiltLibsDir` | *(unset)* | Skip the native build and package `<dir>/<abi>/libscummvm.so` instead. An optional adjacent 16 KB-compatible `libc++_shared.so` is preferred over the selected NDK copy. |

Iterating on the Kotlin layer without rebuilding the engine:

```bash
./gradlew :scummvm:assembleRelease -Pscummvm.prebuiltLibsDir=/path/to/libs
```

### CI

`.github/workflows/ci.yml` has a `build-android` job on `ubuntu-latest`. It
installs the pinned NDK, builds `arm64-v8a` with a representative subset of
engines (a full engine build does not fit comfortably in a CI run), caches the
native build directory against the submodule SHA, builds the release test app
against the just-produced AAR, and uploads both artifacts.

### Development checks

Run focused compilation while editing Kotlin or Compose code:

```bash
./gradlew :scummvm:assembleDebug
./gradlew :app:assembleDebug
```

Before publishing, validate the artifact through the release sample path rather
than only through the local project dependency:

```bash
./gradlew :scummvm:assembleRelease
./gradlew :app:assembleRelease \
  -Pscummvm.releaseAar="$PWD/android/scummvm/build/outputs/aar/scummvm-release.aar"
unzip -l android/scummvm/build/outputs/aar/scummvm-release.aar
```

The AAR must contain `libscummvm.so`, `liboboe.so`, and `libc++_shared.so` for
every requested ABI, along with the staged runtime assets and JNI-facing Java
classes. Repository agent workflows for implementation, failure diagnosis, and
artifact validation live in `.agents/skills/android-compose-development/`,
`.agents/skills/android-build-triage/`, and
`.agents/skills/android-release-checks/`.

## How upstream code is reused

**Native.** All of it, unmodified, via the submodule.

**Java.** A hand-picked subset of `backends/platform/android/org/scummvm/scummvm/`
is copied verbatim into the build by the `stageUpstreamJava` task:
`ScummVM.java` (the JNI contract), `CompatHelpers`, `SAFFSTree`,
`ExternalStorage`, `INIParser`, `Version` and the `net/` package (looked up by
`FindClass` from `backends/networking/basic/android/jni.cpp`, since the Android
port builds without libcurl). Every one of these compiles with no reference to
`ScummVMActivity` and no reference to `R`, which is what makes them safe to ship
in a library.

Upstream's `ScummVMActivity`, `ScummVMEvents`, `SplashActivity`,
`ShortcutCreatorActivity`, `BackupManager`, the custom keyboard views and the
`zip/` package are *not* included: they are launcher-app concerns, need
`dists/android/res/`, and would leak upstream's UI into every consuming app.
Their engine-facing behaviour is reimplemented in Kotlin instead —
`ScummVMHost` (the `ScummVM` subclass the engine calls back into),
`ScummVMInput` (event translation) and `ScummVMAssets` (asset extraction).

One shim is added by hand: `MyScummVMDestroyedCallback`, which upstream declares
at the bottom of `ScummVMActivity.java` but which `ScummVM.java`'s constructor
requires.

## Known limitations

* **One engine host per process.** The native engine is a process-wide
  singleton. `ScummVMEngine` can perform a controlled rerun for archive import,
  but a second engine object still reports `Failed`. Keep the `ScummVM`
  composable in the composition while the user moves between app screens.
* **No on-screen control overlay.** When the engine asks for its menu / input
  mode buttons, the library only logs it; draw your own controls on top of
  `ScummVMView`.
* **Simplified multi-touch.** Two- and three-finger gestures (right and middle
  click) work, but upstream's delayed arbitration between "second finger",
  "third finger" and "two-finger scroll" is not reproduced, so a two-finger
  gesture is reported as soon as the second finger lands.
* **No mouse capture / hover handling.** Upstream's `MouseHelper` is not ported;
  a physical mouse arrives as ordinary pointer events.
* **Backup import/export is reported as cancelled.** It needs upstream's
  `BackupManager`, a document picker and an app restart.
* **Simplified IME integration.** The surface requests raw key events via a
  `TYPE_NULL` input connection; upstream's `EditableSurfaceView` carries extra
  workarounds for specific Latin IMEs.
* **The AAR is large** (~80 MB), dominated by `fonts-cjk.dat` and the bundled
  soundfont. Trim the asset list in `stageScummVMAssets` if your app does not
  need them.
* `scummvm.ini` is only seeded on first run; `gamesDirectory` never overwrites a
  configuration the user already has.
