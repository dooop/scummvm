---
mode: agent
description: Safely maintain ScummVM plugin and detection table overrides. Use when updating swift/Sources/ScummVMEngineOverrides/engines/plugins_table.h or detection_table.h, especially after upstream syncs or engine enable/disable changes.
---

# Plugins Table Maintainer

Maintain generated plugin/detection tables without breaking engine registration.

## Guardrails

- Treat `plugins_table.h` and `detection_table.h` as generated-style data.
- Preserve macro structure used by upstream inclusion sites.
- Avoid unrelated reformatting.

## Workflow

1. Determine why the table needs change:
   - upstream sync drift
   - wrapper-specific engine exclusion
   - compile failure tied to a plugin entry
2. Compare override table(s) with upstream equivalents.
3. Apply narrow edits only to affected entries.
4. Preserve conditional form:
   - `#if defined(ENABLE_X) || defined(DETECTION_FULL)`
   - `LINK_PLUGIN(X)`
5. Rebuild to verify plugin registration compiles and links.

## Consistency Checks

- No duplicate plugin macro entries.
- No broken preprocessor blocks.
- Engine token names remain exact and uppercase.
- Detection and plugin table changes stay logically aligned.

## Report Back

List exactly which engine/plugin entries changed and why.
