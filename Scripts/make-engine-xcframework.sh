#!/usr/bin/env bash
#
# Combines the per-slice static frameworks produced by build-engine-slice.sh into
# distributable XCFrameworks, zips them and prints the SwiftPM checksums that go into
# Package.swift.
#
# Two XCFrameworks rather than one: a framework's module name is its bundle name, and
# the Swift sources import ScummVMiOS on iOS/tvOS but ScummVMmacOS on macOS. An
# XCFramework cannot mix bundle names across slices.
#
# Note that the runtime payload is duplicated once per slice - that is inherent to the
# XCFramework layout, where every slice is a complete framework bundle.
#
# usage: make-engine-xcframework.sh <slices-dir> <output-dir>
#   slices-dir  contains <slice-id>/<Module>.framework, as uploaded by the build jobs
#   output-dir  receives <Module>.xcframework.zip plus checksums.txt
#
set -euo pipefail

if [ "$#" -ne 2 ]; then
  sed -n '2,14p' "$0" >&2
  exit 2
fi

SLICES_DIR="$(cd "$1" && pwd)"
OUTPUT_DIR="$2"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: > "$OUTPUT_DIR/checksums.txt"

# compute-checksum loads the manifest. In binary mode that manifest points at the
# release this script is about to produce, so keep it in source mode here.
export SCUMMVM_BUILD_FROM_SOURCE=1

# module -> slices it is built for
build_xcframework() {
  local module="$1"; shift
  local args=()
  local slice

  for slice in "$@"; do
    local framework="$SLICES_DIR/$slice/$module.framework"
    if [ ! -d "$framework" ]; then
      echo "error: missing slice $slice for $module (expected $framework)" >&2
      exit 1
    fi
    args+=(-framework "$framework")
  done

  echo "==> Creating $module.xcframework from ${#} slices"
  rm -rf "$OUTPUT_DIR/$module.xcframework"
  xcodebuild -create-xcframework "${args[@]}" -output "$OUTPUT_DIR/$module.xcframework"

  # SwiftPM expects the .xcframework at the root of the archive, named after the
  # binary target.
  (cd "$OUTPUT_DIR" && rm -f "$module.xcframework.zip" \
    && ditto -c -k --sequesterRsrc --keepParent "$module.xcframework" "$module.xcframework.zip")

  local checksum
  checksum="$(swift package --package-path "$REPO_ROOT" compute-checksum "$OUTPUT_DIR/$module.xcframework.zip")"
  echo "$module $checksum" >> "$OUTPUT_DIR/checksums.txt"
  echo "    $module.xcframework.zip  $(du -h "$OUTPUT_DIR/$module.xcframework.zip" | cut -f1)  $checksum"
}

build_xcframework ScummVMiOS ios-arm64 ios-arm64-simulator tvos-arm64 tvos-arm64-simulator
build_xcframework ScummVMmacOS macos-arm64

# GPLv2+: the binaries must be traceable to the exact sources they were built from.
{
  echo "swift-scummvm prebuilt ScummVM engine"
  echo
  echo "wrapper commit:  $(git -C "$REPO_ROOT" rev-parse HEAD)"
  echo "upstream commit: $(git -C "$REPO_ROOT/Sources/ScummVMEngine" rev-parse HEAD)"
  echo "upstream source: https://github.com/scummvm/scummvm"
  echo
  echo "ScummVM is licensed under the GNU General Public License v2 or later."
  echo "The complete corresponding source for these binaries is the upstream commit"
  echo "above, combined with the overrides in Sources/ScummVMEngineOverrides of the"
  echo "wrapper commit above."
} > "$OUTPUT_DIR/SOURCES.txt"

echo
echo "==> Artifacts in $OUTPUT_DIR"
cat "$OUTPUT_DIR/checksums.txt"
