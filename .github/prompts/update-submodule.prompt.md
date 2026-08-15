# Skill: Update the ScummVMEngine submodule

Use this skill when pulling a new commit of the upstream ScummVM submodule into
`scummvm/`. The goal is to absorb upstream changes without breaking the
build or silently invalidating existing overrides.

## Step 1: Record the current submodule commit

```sh
git -C ScummVMEngine rev-parse HEAD
```

Save this SHA — it is the rollback point.

## Step 2: Update the submodule

```sh
git submodule update --remote ScummVMEngine
```

Check the new commit:
```sh
git -C ScummVMEngine log --oneline -10
```

## Step 3: Check for upstream file additions/removals

Compare the file tree between the old and new commits to find:
- New source files that might be picked up automatically by the `ScummVMEngine`
  target (and may cause duplicate symbol or compile errors).
- Removed source files that are still listed in `Package.swift` exclusions
  (stale entries — harmless but should be cleaned up).

```sh
git -C ScummVMEngine diff --name-status <old-sha> HEAD
```

## Step 4: Check existing overrides against upstream changes

For every file under `Sources/ScummVMEngineOverrides/`, check whether the
corresponding upstream file changed:

```sh
git -C ScummVMEngine diff <old-sha> HEAD -- <upstream-relative-path>
```

If the upstream file changed:
- Review whether the override's `// OVERRIDE:` fix is still needed.
- If the upstream fix landed, delete the override and remove the exclusion from
  `Package.swift`.
- If the upstream file diverged further, update the override as a minimal diff
  from the new upstream version.

## Step 5: Attempt a build

Build for at least one platform to catch new errors introduced by the upstream
change. Use the `diagnose-build-failure` skill for any new errors.

## Step 6: Commit the result

Stage the submodule pointer update and any `Package.swift` / override changes
together in a single commit:
```
chore: update ScummVMEngine to <new-sha-short>

- <summary of upstream changes>
- Removed override for X (fix landed upstream)
- Added exclusion for Y (new upstream file conflicts with Z)
```

## Rules
- Never edit files under `scummvm/`.
- Always resolve stale override/exclusion pairs after an update.
