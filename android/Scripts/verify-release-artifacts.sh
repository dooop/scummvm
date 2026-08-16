#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <aar> <apk> <comma-separated-abis>" >&2
    exit 2
}

[ "$#" -eq 3 ] || usage

AAR="$1"
APK="$2"
IFS=',' read -r -a ABIS <<< "$3"

[ -f "$AAR" ] || { echo "Missing AAR: $AAR" >&2; exit 1; }
[ -f "$APK" ] || { echo "Missing APK: $APK" >&2; exit 1; }

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

unzip -q "$AAR" -d "$WORK_DIR/aar"
unzip -q "$APK" -d "$WORK_DIR/apk"

require_file() {
    [ -f "$1" ] || { echo "Missing required artifact entry: $1" >&2; exit 1; }
}

require_file "$WORK_DIR/aar/AndroidManifest.xml"
require_file "$WORK_DIR/aar/classes.jar"
require_file "$WORK_DIR/aar/proguard.txt"
require_file "$WORK_DIR/aar/assets/MD5SUMS"
require_file "$WORK_DIR/aar/assets/assets/scummmodern.zip"
require_file "$WORK_DIR/aar/assets/assets/translations.dat"
require_file "$WORK_DIR/aar/assets/assets/pred.dic"

if grep -Eq '<(application|uses-feature|uses-permission)([[:space:]>])' "$WORK_DIR/aar/AndroidManifest.xml"; then
    echo "The library manifest must not add application, feature, or permission declarations." >&2
    exit 1
fi

CLASSES="$(jar tf "$WORK_DIR/aar/classes.jar")"
for class in \
    org/scummvm/ScummVMKt.class \
    org/scummvm/ScummVMConfiguration.class \
    org/scummvm/ScummVMEngine.class \
    org/scummvm/ScummVMViewKt.class \
    org/scummvm/scummvm/ScummVM.class \
    org/scummvm/scummvm/ScummVMHost.class \
    org/scummvm/scummvm/net/HTTPManager.class; do
    grep -qx "$class" <<< "$CLASSES" || {
        echo "Missing required class: $class" >&2
        exit 1
    }
done

READELF="${READELF:-}"
if [ -z "$READELF" ] && [ -n "${ANDROID_NDK_ROOT:-}" ]; then
    READELF="$(find "$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt" -path '*/bin/llvm-readelf' -type f -print -quit)"
fi
[ -x "$READELF" ] || {
    echo "Set READELF or ANDROID_NDK_ROOT so ELF architecture and alignment can be checked." >&2
    exit 1
}

expected_machine() {
    case "$1" in
        arm64-v8a) echo "AArch64" ;;
        armeabi-v7a) echo "ARM" ;;
        x86) echo "Intel 80386" ;;
        x86_64) echo "Advanced Micro Devices X86-64" ;;
        *) echo "Unsupported ABI: $1" >&2; exit 1 ;;
    esac
}

check_elf() {
    local library="$1"
    local abi="$2"
    local machine
    local actual_machine
    local alignments
    machine="$(expected_machine "$abi")"

    actual_machine="$("$READELF" -h "$library" | awk -F: '$1 ~ /Machine/ { sub(/^[ \t]+/, "", $2); print $2 }')"
    [ "$actual_machine" = "$machine" ] || {
        echo "Wrong architecture for $library (expected $machine, found $actual_machine)." >&2
        exit 1
    }

    alignments="$("$READELF" -lW "$library" | awk '$1 == "LOAD" { print $NF }')"
    [ -n "$alignments" ] || { echo "No LOAD segments found in $library" >&2; exit 1; }
    while read -r alignment; do
        [ "$((alignment))" -ge "$((0x4000))" ] || {
            echo "$library has LOAD alignment $alignment; 0x4000 is required." >&2
            exit 1
        }
    done <<< "$alignments"
}

EXPECTED_ABIS="$(printf '%s\n' "${ABIS[@]}" | sort)"
AAR_ABIS="$(find "$WORK_DIR/aar/jni" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)"
APK_ABIS="$(find "$WORK_DIR/apk/lib" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)"

[ "$AAR_ABIS" = "$EXPECTED_ABIS" ] || {
    echo "AAR ABIs differ. Expected: ${ABIS[*]}; found: $(tr '\n' ' ' <<< "$AAR_ABIS")" >&2
    exit 1
}
[ "$APK_ABIS" = "$EXPECTED_ABIS" ] || {
    echo "APK ABIs differ. Expected: ${ABIS[*]}; found: $(tr '\n' ' ' <<< "$APK_ABIS")" >&2
    exit 1
}

for abi in "${ABIS[@]}"; do
    AAR_LIBRARIES="$(find "$WORK_DIR/aar/jni/$abi" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | sort)"
    EXPECTED_LIBRARIES="$(printf '%s\n' libc++_shared.so liboboe.so libscummvm.so | sort)"
    [ "$AAR_LIBRARIES" = "$EXPECTED_LIBRARIES" ] || {
        echo "Unexpected native library set for $abi: $(tr '\n' ' ' <<< "$AAR_LIBRARIES")" >&2
        exit 1
    }
    for name in libscummvm.so liboboe.so libc++_shared.so; do
        require_file "$WORK_DIR/aar/jni/$abi/$name"
        require_file "$WORK_DIR/apk/lib/$abi/$name"
        check_elf "$WORK_DIR/aar/jni/$abi/$name" "$abi"
    done
done

echo "Verified AAR: $AAR"
echo "Verified APK: $APK"
echo "ABIs: ${ABIS[*]}"
echo "Native libraries, runtime assets, wrapper/JNI classes, consumer rules, architectures, and 16 KB alignment are valid."
