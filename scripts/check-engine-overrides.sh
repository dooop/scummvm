#!/usr/bin/env bash
#
# Audits swift/Sources/ScummVMEngineOverrides/ against the scummvm submodule.
#
# For every override that replaces an upstream file, finds the upstream revision it
# was copied from (the historical version with the smallest diff to the override)
# and reports how many upstream commits have touched the file since. A non-zero
# count means the override is missing upstream changes; a zero-line diff against
# HEAD means the override no longer changes anything and can be dropped.
# Translation units must also be excluded in Package.swift, or both copies compile.
#
# Overrides without an upstream counterpart (preinclude shims, *_main_override.cpp
# wrappers, generated tables) are listed separately; for wrappers the script checks
# that the upstream file they #include still exists and is excluded.
#
# usage: check-engine-overrides.sh [--merge]
#   --merge  3-way-merge upstream changes since the base revision into every
#            drifted override (git merge-file; conflict markers are left in place)
#
# Exits 1 when any override needs attention.
#
set -euo pipefail

MERGE=0
case "${1:-}" in
  "") ;;
  --merge) MERGE=1 ;;
  *) sed -n '2,21p' "$0" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERRIDES="$REPO_ROOT/swift/Sources/ScummVMEngineOverrides"
SUBMODULE="$REPO_ROOT/scummvm"
PACKAGE="$REPO_ROOT/Package.swift"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [ ! -e "$SUBMODULE/.git" ]; then
  echo "error: scummvm submodule is not initialized" >&2
  exit 2
fi

diff_lines() {
  diff "$1" "$2" | grep -c '^[<>]' || true
}

# Header overrides win through the ScummVMEngineOverrides header search path, which
# sits next to ScummVMEngine/engines, so "titanic/..." can shadow "engines/titanic/...".
upstream_path() {
  local rel="$1"
  if [ -f "$SUBMODULE/$rel" ]; then
    echo "$rel"
  elif [ -f "$SUBMODULE/engines/$rel" ]; then
    echo "engines/$rel"
  fi
}

# True when the upstream path, or one of its parent directories, is excluded.
is_excluded() {
  local path="$1"
  while [ "$path" != . ]; do
    grep -qF "\"ScummVMEngine/$path\"" "$PACKAGE" && return 0
    path="$(dirname "$path")"
  done
  return 1
}

attention=0
wrappers=()

printf '%-55s %-10s %-11s %6s %6s  %s\n' OVERRIDE BASE BASE-DATE BEHIND OWN STATUS
while IFS= read -r rel; do
  up="$(upstream_path "$rel")"
  if [ -z "$up" ]; then
    wrappers+=("$rel")
    continue
  fi

  best_sha="" best_lines=""
  while IFS= read -r sha; do
    if ! git -C "$SUBMODULE" show "$sha:$up" > "$WORK_DIR/candidate" 2>/dev/null; then
      continue
    fi
    n="$(diff_lines "$WORK_DIR/candidate" "$OVERRIDES/$rel")"
    if [ -z "$best_lines" ] || [ "$n" -lt "$best_lines" ]; then
      best_sha="$sha" best_lines="$n"
      cp "$WORK_DIR/candidate" "$WORK_DIR/base"
    fi
    [ "$n" -eq 0 ] && break
  done < <(git -C "$SUBMODULE" log --format=%H -n 400 -- "$up")

  behind="$(git -C "$SUBMODULE" rev-list --count "$best_sha..HEAD" -- "$up")"
  head_lines="$(diff_lines "$SUBMODULE/$up" "$OVERRIDES/$rel")"
  status=ok

  if [ "$head_lines" -eq 0 ]; then
    status="OBSOLETE: identical to upstream HEAD"
  elif [ "$behind" -gt 0 ]; then
    status="DRIFTED: upstream changed since base"
    if [ "$MERGE" -eq 1 ]; then
      if git merge-file "$OVERRIDES/$rel" "$WORK_DIR/base" "$SUBMODULE/$up"; then
        status="MERGED: re-check the diff"
      else
        status="MERGED WITH CONFLICTS: resolve markers"
      fi
    fi
  fi

  case "$rel" in
    *.c|*.cpp|*.m|*.mm)
      if ! is_excluded "$up"; then
        status="$status; NOT EXCLUDED in Package.swift"
      fi
      ;;
  esac

  [ "$status" = ok ] || attention=1
  printf '%-55s %-10s %-11s %6s %6s  %s\n' "$rel" "${best_sha:0:10}" \
    "$(git -C "$SUBMODULE" log -1 --format=%as "$best_sha")" "$behind" "$best_lines" "$status"
done < <(cd "$OVERRIDES" && find . -type f ! -name '.*' | sed 's|^\./||' | sort)

echo
echo "Overrides without an upstream counterpart:"
for rel in "${wrappers[@]}"; do
  status=""
  while IFS= read -r inc; do
    inc="${inc#ScummVMEngine/}"
    if [ ! -f "$SUBMODULE/$inc" ]; then
      status="MISSING #include target: $inc"
    elif ! is_excluded "$inc"; then
      status="#include target NOT EXCLUDED in Package.swift: $inc"
    fi
  done < <(sed -n 's/^#include "\(.*\.cpp\)"$/\1/p' "$OVERRIDES/$rel")
  [ -z "$status" ] || attention=1
  printf '  %-53s %s\n' "$rel" "${status:-wrapper/shim, review by hand}"
done

exit "$attention"
