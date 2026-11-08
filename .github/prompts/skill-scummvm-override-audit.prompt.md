---
mode: agent
description: Periodically audit swift/Sources/ScummVMEngineOverrides/ for overrides that have become obsolete or fallen behind upstream. Use after every scummvm submodule bump, when an override-related build error appears, or as a recurring health check of the override set and its Package.swift exclusions.
---

# ScummVM Override Audit

Overrides are copies of upstream files. Every one of them silently stops receiving upstream fixes, so each must keep earning its place.

## Guardrails

- Never edit files under `scummvm/`.
- Prefer deleting an override over keeping it. A `Package.swift` exclusion, define or preinclude is always cheaper than a copied file.
- Keep surviving overrides as minimal diffs against the *current* upstream file.

## Workflow

1. Make sure the submodule is checked out: `git submodule update --init scummvm`.
2. Run `scripts/check-engine-overrides.sh`. It takes about a minute and exits 1 when something needs attention. For each override with an upstream peer, it prints:
   - **BASE**: the upstream revision the override was copied from (the version with the smallest diff).
   - **BEHIND**: upstream commits to that file since BASE.
   - **OWN**: the wrapper's own diff size.
   - **STATUS** one of:
     - `OBSOLETE`: identical to upstream HEAD. Delete it.
     - `DRIFTED`: upstream fixes are missing. Re-sync it (step 4).
     - `NOT EXCLUDED`: the upstream translation unit is not in `Package.swift`'s `exclude`, so both copies compile and you get duplicate symbols.
3. For every row, including `ok` ones, read the diff against upstream (`diff scummvm/<path> swift/Sources/ScummVMEngineOverrides/<path>`) and ask whether its reason still holds. A small OWN diff often means upstream has fixed the problem in a way the script can't detect. Obsolescence patterns seen so far:
   - Upstream fixed the root cause:
     - A declaration was moved out of an `#ifdef` (the `gui/EventRecorder.cpp` override).
     - A member changed type, which made a cast a no-op (`gui/downloaddlcsdialog.cpp`).
     - A platform guard was added (`ios7_osys_video.mm`'s `isiOSAppOnMac`).
   - The override duplicates a mechanism the package already applies globally: the `ScummVMAGSAlconfigBridge.h` preinclude made the `engines/ags/lib/allegro/fmaths.h` override redundant.
   - The override only exists to make an orphan file compile: `titanic/game/pet/pet_val_base.h` existed only so `pet_val_base.cpp` would build. If upstream's `module.mk` never builds the file, exclude it instead (`grep <name>.o scummvm/<dir>/module.mk`).
   - The override only renames a base-class call, and both names resolve to the same method. Check where the method is actually defined before keeping such a diff.
4. For `DRIFTED` overrides that are still needed, run `scripts/check-engine-overrides.sh --merge`. It 3-way-merges upstream's changes since BASE into the override with `git merge-file`. Resolve any conflict markers. Then make sure OWN did not grow, which would mean the merge dragged in wrapper-unrelated churn.
5. To delete an override, remove:
   - the file, and any empty directories it leaves behind;
   - its `exclude` entry, including the comment;
   - any `sources:` path pointing at it. For ios7 files, switch the `ScummVMiOS` sources entry back to `ScummVMEngine/...`.
6. Find leftover references with `grep -rn <file> Package.swift README.md CLAUDE.md .agents .github`.
7. Rerun the script until it exits 0.

## Still-required patterns (don't "clean up")

- **Event-recorder overrides** (`recorderfile.cpp`, `recorder-saves.cpp`, `onscreendialog.cpp`, `recorderdialog.cpp`): `ENABLE_EVENTRECORDER` is macOS-only, and SwiftPM `exclude` can't be conditioned on platform. These overrides replace upstream's `module.mk` `ifdef` gating, so they stay.
- **`*_main_override.cpp`**: these only `#include` an upstream `main.cpp`, to avoid basename collisions in one SwiftPM target. They stay as long as several `main.cpp` files exist. The script checks that the target exists and is excluded.
- **Shims** (`ScummVMNoObjCMacros.h`, `ScummVMObjCYesNoConsts.h`, `ScummVMAGSAlconfigBridge.h`, `codec.h`, `common/types.h`): these are build glue for Objective-C `YES`/`NO` macros, preincludes and XCFramework header layout. Review by hand.
- **`engines/plugins_table.h`, `engines/detection_table.h`**: see `plugins-table-maintainer`.

## Verification

- `scripts/check-engine-overrides.sh` exits 0.
- `swift package dump-package > /dev/null` succeeds. It catches stale `exclude` and `sources` paths.
- If you changed any override or exclusion, run a source-mode build on macOS and at least one iOS/tvOS slice (`SCUMMVM_BUILD_FROM_SOURCE=1`), or let CI's source-build tier run it. These changes reach consumers only with the next engine release.

## Report Back

List the overrides you removed (with the reason each became unnecessary), the overrides you re-synced (with the upstream commits picked up), any `Package.swift` exclude or sources changes, and the build status.
