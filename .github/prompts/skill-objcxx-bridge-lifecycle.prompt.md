---
mode: agent
description: Maintain SwiftUI to ObjC++ lifecycle integration. Use when changing start/stop behavior, UI bridging, singleton setup, threading, or platform glue in Sources/ScummVM, Sources/ScummVMiOS, Sources/ScummVMmacOS, or Sources/ScummVMtvOS.
---

# ObjC++ Bridge Lifecycle

Keep SwiftUI lifecycle and engine lifecycle coherent across platforms.

## Guardrails

- Keep public API unchanged unless explicitly requested.
- Preserve singleton access via `ScummVMEngineSharedInstance()`.
- Preserve platform split:
  - iOS/tvOS bridge returns `UIViewController`
  - macOS bridge does not embed SDL content in `NSView`

## Workflow

1. Trace lifecycle flow end-to-end:
   - `ScummVM` appear/disappear
   - bridge start/stop entrypoints
   - `ScummVMAppContext` setup and runtime launch
2. Verify thread affinity before edits:
   - UI object creation on main thread
   - synchronized start/stop state transitions
3. Make minimal platform-specific changes in the corresponding target.
4. Keep manual C-string argv allocation/free balanced where runtime args are bridged.
5. Re-check idempotency for repeated `start()`/`stop()` calls.

## High-Risk Areas

- Dispatching ScummVM startup on a queue that violates backend assumptions.
- Returning nil UI bridges without fallback host view/controller.
- Destroying `g_system` from a non-main path when backend expects main-thread teardown.

## Verification

- Build affected platform targets.
- Run basic lifecycle sequence: create view, appear/start, disappear/stop, re-appear/start.
- Confirm no duplicate startup or leaked engine state.
