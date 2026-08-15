#!/usr/bin/env bash
#
# Builds one platform slice of the prebuilt ScummVM engine and assembles it into a
# dynamic .framework that xcodebuild -create-xcframework can consume.
#
# Dynamic rather than static, for one reason: a static framework is never copied into
# the consuming app, so anything in its Resources directory is dropped. The engine's
# runtime payload (engine-data, themes, soundfonts) has to travel with the binary,
# because binary-mode consumers have no ScummVM submodule to copy it from.
#
# The dylib also absorbs the third-party static libraries and links the system
# frameworks itself, so the consumer's package graph shrinks to two artifacts.
#
# usage: build-engine-slice.sh <scheme> <slice-id> <output-dir> [product-name]
#   scheme       ScummVMiOS | ScummVMmacOS  (Xcode scheme to archive)
#   slice-id     ios-arm64 | ios-arm64-simulator | tvos-arm64 |
#                tvos-arm64-simulator | macos-arm64
#   output-dir   receives <product-name>.framework
#   product-name output framework/module name, defaults to scheme. Lets the tvOS
#                slices ship as a distinct ScummVMtvOS.framework built from the
#                ScummVMiOS Xcode target/source, so iOS and tvOS can be published as
#                two separate XCFrameworks instead of one that bundles both.
#
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  sed -n '2,22p' "$0" >&2
  exit 2
fi

SCHEME="$1"
SLICE_ID="$2"
OUTPUT_DIR="$3"
PRODUCT="${4:-$SCHEME}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE="$REPO_ROOT/scummvm"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [ "$(uname -m)" != "arm64" ]; then
  echo "error: engine slices are supported only on Apple Silicon hosts" >&2
  exit 1
fi

ARCHIVE_PATH="$WORK_DIR/$SLICE_ID.xcarchive"
DERIVED_DATA="$WORK_DIR/DerivedData"
FRAMEWORK="$OUTPUT_DIR/$PRODUCT.framework"

# The manifest defaults to consuming the prebuilt engine; the release pipeline is the
# one place that has to compile it.
export SCUMMVM_BUILD_FROM_SOURCE=1

IS_MACOS=0
IS_SIMULATOR=0
case "$SLICE_ID" in
  ios-arm64)
    SDK=iphoneos;          DESTINATION="generic/platform=iOS"
    TRIPLE="arm64-apple-ios17.0"
    SUPPORTED_PLATFORM="iPhoneOS";        MIN_OS="17.0"; PLATFORM=ios ;;
  ios-arm64-simulator)
    SDK=iphonesimulator;   DESTINATION="generic/platform=iOS Simulator"
    TRIPLE="arm64-apple-ios17.0-simulator"
    SUPPORTED_PLATFORM="iPhoneSimulator"; MIN_OS="17.0"; PLATFORM=ios; IS_SIMULATOR=1 ;;
  tvos-arm64)
    SDK=appletvos;         DESTINATION="generic/platform=tvOS"
    TRIPLE="arm64-apple-tvos17.0"
    SUPPORTED_PLATFORM="AppleTVOS";       MIN_OS="17.0"; PLATFORM=tvos ;;
  tvos-arm64-simulator)
    SDK=appletvsimulator;  DESTINATION="generic/platform=tvOS Simulator"
    TRIPLE="arm64-apple-tvos17.0-simulator"
    SUPPORTED_PLATFORM="AppleTVSimulator"; MIN_OS="17.0"; PLATFORM=tvos; IS_SIMULATOR=1 ;;
  macos-arm64)
    SDK=macosx;            DESTINATION="generic/platform=macOS"
    TRIPLE="arm64-apple-macos15.0"
    SUPPORTED_PLATFORM="MacOSX";          MIN_OS="15.0"; PLATFORM=macos; IS_MACOS=1 ;;
  *) echo "error: unknown slice id '$SLICE_ID'" >&2; exit 2 ;;
esac

echo "==> Archiving $SCHEME for $SLICE_ID"
cd "$REPO_ROOT"
xcodebuild archive \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  SKIP_INSTALL=NO \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS=arm64 \
  EXCLUDED_ARCHS=x86_64 \
  DEBUG_INFORMATION_FORMAT=dwarf \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

# SwiftPM library targets archive as one relocatable object per target. Older
# toolchains may emit static archives instead, so accept both forms while requiring
# exactly the engine and platform-glue products we need.
ENGINE_PRODUCTS=()
for target in ScummVMEngine "$SCHEME"; do
  product="$(find "$ARCHIVE_PATH/Products" -type f \
    \( -name "$target.o" -o -name "lib$target.a" \) -print -quit)"
  if [ -z "$product" ]; then
    echo "error: archive did not contain $target.o or lib$target.a" >&2
    find "$ARCHIVE_PATH/Products" -maxdepth 8 -type f -print >&2 || true
    exit 1
  fi
  ENGINE_PRODUCTS+=("$product")
done
echo "==> Engine products: ${ENGINE_PRODUCTS[*]##*/}"

# The third-party dependencies are remote binary targets. Resolve each one's slice for
# this platform out of the SwiftPM artifact cache; their xcframeworks still carry
# x86_64 in the slice directory names, so match on the Info.plist rather than on the
# directory name.
THIRD_PARTY=(a52 bz2 curl faad ffi FLAC fluidsynth freetype fribidi gif glib-2.0
             intl jpeg mad mikmod mpeg2 ogg png SDL2_net theoradec vorbis
             vorbisfile vpx)
if [ "$IS_MACOS" -eq 1 ]; then
  THIRD_PARTY+=(SDL2)
fi

find_xcframework() {
  local name="$1"
  local candidate
  for root in "$DERIVED_DATA/SourcePackages/artifacts" "$REPO_ROOT/.build/artifacts"; do
    [ -d "$root" ] || continue
    while IFS= read -r candidate; do
      if [ -f "$candidate/Info.plist" ]; then
        echo "$candidate"
        return 0
      fi
    done < <(find "$root" -maxdepth 4 -type d -name "$name.xcframework" \
      -not -path '*/__MACOSX/*' -print)
  done
  return 1
}

select_slice_library() {
  # Reads the xcframework Info.plist and returns the library path for this platform,
  # variant and arm64.
  python3 - "$1" "$PLATFORM" "$IS_SIMULATOR" <<'PY'
import os, plistlib, sys

xcframework, platform, is_simulator = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
with open(os.path.join(xcframework, "Info.plist"), "rb") as handle:
    info = plistlib.load(handle)

for library in info.get("AvailableLibraries", []):
    if library.get("SupportedPlatform") != platform:
        continue
    if (library.get("SupportedPlatformVariant") == "simulator") != is_simulator:
        continue
    if "arm64" not in library.get("SupportedArchitectures", []):
        continue
    print(os.path.join(xcframework,
                       library["LibraryIdentifier"],
                       library["LibraryPath"]))
    break
PY
}

THIRD_PARTY_LIBS=()
for name in "${THIRD_PARTY[@]}"; do
  xcframework="$(find_xcframework "$name")" || {
    echo "error: $name.xcframework not found - run 'swift package resolve' first" >&2
    exit 1
  }
  lib="$(select_slice_library "$xcframework")"
  if [ -z "$lib" ] || [ ! -e "$lib" ]; then
    echo "error: $name.xcframework has no arm64 slice for $SLICE_ID" >&2
    exit 1
  fi
  THIRD_PARTY_LIBS+=("$lib")
done
echo "==> Linking against ${#THIRD_PARTY_LIBS[@]} third-party libraries"

# Keep in sync with the ScummVMEngine target's linkerSettings in Package.swift.
SYSTEM_FLAGS=(-lc++ -lz -liconv
  -framework AudioToolbox -framework CoreAudio -framework CoreFoundation
  -framework CoreGraphics -framework CoreMIDI -framework Foundation
  -framework GameController -framework QuartzCore -framework Security
  -framework SystemConfiguration)
if [ "$IS_MACOS" -eq 1 ]; then
  SYSTEM_FLAGS+=(-llber -lldap
    -framework AppKit -framework OpenGL -framework Metal -framework CoreHaptics
    -framework ForceFeedback -framework AudioUnit -framework Cocoa -framework Carbon
    -framework ApplicationServices -framework IOKit)
else
  SYSTEM_FLAGS+=(-framework OpenGLES -framework UIKit)
fi

# Relocatable objects are linked directly and already contain every target object.
# Static-archive output from older toolchains still needs force_load because nothing
# outside the dylib references the plugin and detection tables.
ENGINE_LINK_FLAGS=()
for product in "${ENGINE_PRODUCTS[@]}"; do
  case "$product" in
    *.a) ENGINE_LINK_FLAGS+=(-Wl,-force_load,"$product") ;;
    *)   ENGINE_LINK_FLAGS+=("$product") ;;
  esac
done

echo "==> Linking $SCHEME dylib ($TRIPLE)"
DYLIB="$WORK_DIR/$SCHEME"
xcrun --sdk "$SDK" clang++ \
  -dynamiclib \
  -target "$TRIPLE" \
  -isysroot "$(xcrun --sdk "$SDK" --show-sdk-path)" \
  -install_name "@rpath/$PRODUCT.framework/$PRODUCT" \
  -compatibility_version 1 -current_version 1 \
  "${ENGINE_LINK_FLAGS[@]}" \
  "${THIRD_PARTY_LIBS[@]}" \
  "${SYSTEM_FLAGS[@]}" \
  -o "$DYLIB"

strip -x -S "$DYLIB"

# force_load is what keeps the engines in: nothing references the plugin and detection
# tables from outside. If it ever stops working the link still succeeds and the app
# simply finds no games at runtime, so check here rather than downstream.
MISSING=0
SYMBOLS_FILE="$WORK_DIR/$SCHEME.symbols"
nm -gU "$DYLIB" > "$SYMBOLS_FILE"
for symbol in ScummEngine SciEngine AGSEngine scummvm_main; do
  if ! grep -q "$symbol" "$SYMBOLS_FILE"; then
    echo "error: '$symbol' missing from the linked dylib - engine objects were dropped" >&2
    MISSING=1
  fi
done
[ "$MISSING" -eq 0 ] || exit 1

echo "==> Assembling $PRODUCT.framework"
rm -rf "$FRAMEWORK"
if [ "$IS_MACOS" -eq 1 ]; then
  # macOS requires the versioned bundle layout.
  BUNDLE_ROOT="$FRAMEWORK/Versions/A"
  RESOURCES="$BUNDLE_ROOT/Resources"
  PLIST="$RESOURCES/Info.plist"
else
  BUNDLE_ROOT="$FRAMEWORK"
  RESOURCES="$FRAMEWORK"
  PLIST="$FRAMEWORK/Info.plist"
fi
mkdir -p "$BUNDLE_ROOT/Headers" "$BUNDLE_ROOT/Modules" "$RESOURCES"

cp "$DYLIB" "$BUNDLE_ROOT/$PRODUCT"
cp "$REPO_ROOT/Sources/$SCHEME/include/ScummVMEngine.h" "$BUNDLE_ROOT/Headers/"

cat > "$BUNDLE_ROOT/Modules/module.modulemap" <<EOF
framework module $PRODUCT {
  header "ScummVMEngine.h"
  export *
}
EOF

# Runtime payload, straight from the submodule. Mirrors the resource rules on the
# ScummVMEngine/ScummVMiOS/ScummVMmacOS targets in Package.swift - keep them in sync.
# The backend finds these by recursively scanning the bundle for engine_data_core.mk
# and scummmodern.zip, so engine-data stays the only subdirectory.
echo "==> Copying runtime payload"
rsync -a --exclude '.DS_Store' "$SUBMODULE/dists/engine-data" "$RESOURCES/"
cp "$SUBMODULE/dists/networking/wwwroot.zip" "$RESOURCES/"
cp "$SUBMODULE/dists/soundfonts/Roland_SC-55.sf2" "$RESOURCES/"
cp "$SUBMODULE/dists/soundfonts/COPYRIGHT.Roland_SC-55" "$RESOURCES/"
cp "$SUBMODULE/dists/pred.dic" "$RESOURCES/"
for theme in gui-icons.dat residualvm.zip scummclassic.zip scummmodern.zip \
             scummremastered.zip shaders.dat translations.dat; do
  cp "$SUBMODULE/gui/themes/$theme" "$RESOURCES/"
done

case "$SLICE_ID" in
  ios-*)
    # Copied raw rather than compiled with actool: the ios7_video.mm override reads the
    # ic_action_* icons straight out of Images.xcassets/<name>.imageset/<name>.pdf.
    rsync -a --exclude '.DS_Store' "$SUBMODULE/dists/ios7/Images.xcassets" "$RESOURCES/"
    cp "$SUBMODULE/dists/ios7/PrivacyInfo.xcprivacy" "$RESOURCES/"
    ;;
  tvos-*)
    rsync -a --exclude '.DS_Store' "$SUBMODULE/dists/tvos/Images.xcassets" "$RESOURCES/"
    cp "$SUBMODULE/dists/tvos/PrivacyInfo.xcprivacy" "$RESOURCES/"
    ;;
  macos-*)
    cp "$SUBMODULE/dists/macosx/dsa_pub.pem" "$RESOURCES/"
    ;;
esac

VERSION="$(git -C "$REPO_ROOT" describe --tags --always --dirty 2>/dev/null || echo 0.0.0)"
ENGINE_SHA="$(git -C "$SUBMODULE" rev-parse HEAD 2>/dev/null || echo unknown)"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$PRODUCT</string>
  <key>CFBundleIdentifier</key><string>dev.dooop.swift-scummvm.$PRODUCT</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$PRODUCT</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$SUPPORTED_PLATFORM</string></array>
  <key>MinimumOSVersion</key><string>$MIN_OS</string>
  <key>SCVMWrapperVersion</key><string>$VERSION</string>
  <key>SCVMUpstreamCommit</key><string>$ENGINE_SHA</string>
</dict>
</plist>
EOF

if [ "$IS_MACOS" -eq 1 ]; then
  ln -s A "$FRAMEWORK/Versions/Current"
  ln -s "Versions/Current/$PRODUCT" "$FRAMEWORK/$PRODUCT"
  ln -s Versions/Current/Headers "$FRAMEWORK/Headers"
  ln -s Versions/Current/Modules "$FRAMEWORK/Modules"
  ln -s Versions/Current/Resources "$FRAMEWORK/Resources"
fi

echo "==> Done: $FRAMEWORK"
echo "    binary $(du -h "$BUNDLE_ROOT/$PRODUCT" | cut -f1), bundle $(du -sh "$FRAMEWORK" | cut -f1), upstream $ENGINE_SHA"
