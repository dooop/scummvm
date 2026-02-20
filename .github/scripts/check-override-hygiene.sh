#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PACKAGE_FILE="Package.swift"
errors=0

engine_excludes=()
while IFS= read -r exclude_entry; do
  engine_excludes+=("$exclude_entry")
done < <(
  awk '
    BEGIN { in_engine_target = 0; in_excludes = 0 }
    !in_engine_target && /name:[[:space:]]*"ScummVMEngine"/ { in_engine_target = 1 }
    in_engine_target && !in_excludes && /exclude:[[:space:]]*\[/ { in_excludes = 1; next }
    in_excludes {
      if ($0 ~ /^[[:space:]]*\],/) {
        exit
      }
      line = $0
      while (match(line, /"[^"]+"/)) {
        entry = substr(line, RSTART + 1, RLENGTH - 2)
        print entry
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$PACKAGE_FILE"
)

is_engine_excluded() {
  local rel="$1"
  local ex
  for ex in "${engine_excludes[@]}"; do
    if [[ "$rel" == "$ex" || "$rel" == "$ex"/* ]]; then
      return 0
    fi
  done
  return 1
}

count_manifest_refs() {
  local rel="$1"
  (rg -F "\"$rel\"" "$PACKAGE_FILE" || true) | wc -l | tr -d ' '
}

report_error() {
  printf 'ERROR: %s\n' "$1" >&2
  errors=$((errors + 1))
}

# No excludes should point to missing override paths.
for ex in "${engine_excludes[@]}"; do
  if [[ "$ex" == ScummVMEngineOverrides/* ]] && [[ ! -e "Sources/$ex" ]]; then
    report_error "ScummVMEngine exclude references missing override path: Sources/$ex"
  fi
done

while IFS= read -r source_file; do
  rel="${source_file#Sources/}"
  refs="$(count_manifest_refs "$rel")"

  # If engine excludes this override and no other target uses it, it is stale.
  if is_engine_excluded "$rel"; then
    if (( refs <= 1 )); then
      report_error "Stale override source is excluded and unused: $source_file"
    fi
    continue
  fi

  local_subpath="${rel#ScummVMEngineOverrides/}"
  source_dir="$(dirname "$local_subpath")"
  source_base="$(basename "$local_subpath")"

  if [[ "$source_base" == *_main_override.cpp ]]; then
    upstream_rel="ScummVMEngine/$source_dir/main.cpp"
  else
    upstream_rel="ScummVMEngine/$local_subpath"
  fi

  if [[ -f "Sources/$upstream_rel" ]] && ! is_engine_excluded "$upstream_rel"; then
    report_error "Override source does not have matching upstream exclusion: Sources/$source_file -> Sources/$upstream_rel"
  fi
done < <(find Sources/ScummVMEngineOverrides -type f \( -name '*.cpp' -o -name '*.mm' \) | sort)

if (( errors > 0 )); then
  printf '\nOverride hygiene check failed with %d issue(s).\n' "$errors" >&2
  exit 1
fi

echo "Override hygiene check passed."
