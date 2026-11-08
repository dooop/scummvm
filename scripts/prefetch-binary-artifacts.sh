#!/usr/bin/env bash
#
# Downloads every remote binary target of the package (as the current
# SCUMMVM_BUILD_FROM_SOURCE mode declares them) into SwiftPM's shared artifact
# cache, so the following `swift package resolve` copies them from there instead
# of downloading them itself.
#
# SwiftPM downloads all binary targets at once and does not survive slow
# connections: on some GitHub-hosted runners its requests time out, its internal
# retry then trips over the partial file and fails with "... already exists in
# file system". curl retries each file on its own, and SwiftPM still verifies
# every checksum afterwards.
#
# usage: prefetch-binary-artifacts.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${HOME}/Library/Caches/org.swift.swiftpm/artifacts"
mkdir -p "$CACHE_DIR"

# SwiftPM keys cached artifacts by the URL with every character that is not
# valid in a C99 identifier replaced by "_".
cd "$REPO_ROOT"
swift package dump-package | python3 -I -c '
import json, re, sys
for target in json.load(sys.stdin)["targets"]:
    url = target.get("url")
    if url:
        print(url, re.sub(r"[^A-Za-z0-9_]", "_", url))
' > "$CACHE_DIR/.prefetch-list"

fetch() {
  local url="$1" key="$2"
  [ -s "$CACHE_DIR/$key" ] && return 0
  curl --fail --location --silent --show-error \
    --retry 5 --retry-all-errors --retry-delay 5 \
    --connect-timeout 30 --max-time 600 \
    --output "$CACHE_DIR/$key.partial" "$url"
  mv "$CACHE_DIR/$key.partial" "$CACHE_DIR/$key"
  echo "prefetched $url"
}
export -f fetch
export CACHE_DIR

xargs -P 4 -n 2 bash -c 'fetch "$1" "$2"' _ < "$CACHE_DIR/.prefetch-list"
rm -f "$CACHE_DIR/.prefetch-list"
