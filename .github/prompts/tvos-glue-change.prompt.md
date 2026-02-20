# Skill: Make a tvOS glue change

Use this skill when modifying `Sources/ScummVMtvOS/`. tvOS glue is distinct from
iOS glue and must be treated independently.

## Key differences from iOS glue

| Concern | iOS | tvOS |
|---|---|---|
| Input | Touch, keyboard | Remote (Siri Remote), game controller |
| Window/scene lifecycle | UIWindowScene standard | AppleTV focus engine |
| Background audio | Allowed with entitlement | Same |
| Mouse/pointer | UIPointerInteraction | Not available |
| File picker / external storage | UIDocumentPickerViewController | Not available |
| SDL backend | `SDL2` + touch events | `SDL2` + controller events |

Do not copy iOS glue files into tvOS and adjust — start from what tvOS actually
needs.

## Structure

```
Sources/ScummVMtvOS/
    include/
        ScummVMEngine.h    -- public ObjC API (keep minimal and stable)
    *.mm                   -- ObjC++ implementation files
    *.cpp                  -- C++ glue files (if any)
```

## Adding a new feature

1. Determine whether the feature is tvOS-specific or shared with iOS.
   - If shared, consider whether a common abstraction belongs in
     `Sources/ScummVMEngine/` glue rather than duplicating code.
   - If tvOS-specific, implement only in `Sources/ScummVMtvOS/`.

2. Keep the public header (`include/ScummVMEngine.h`) stable. Do not add
   symbols to it without an explicit user request.

3. Do not add main-thread assumptions. The engine currently runs on the main
   thread but will move to a background thread — see copilot-instructions for
   threading guidance.

4. The `start`/`stop` lifecycle is not yet working. Do not depend on it behaving
   correctly; flag any assumptions with a `// TODO: lifecycle not yet implemented`
   comment.

## Controller input

tvOS relies on `GCController` (GameController framework) and the Siri Remote.
When mapping input:
- Use `GCController.controllers()` for connected gamepads.
- Map remote swipes to directional events; the Select button maps to the primary
  action.
- Do not assume a keyboard is present.

## Thread-crossing

Any call from a `GCController` callback or display-link into ScummVM must be
marshalled correctly. Document the threading contract at the call site.

## Testing checklist

- [ ] Builds for `tvOS-arm64` device slice.
- [ ] Builds for `tvOS-simulator` slice (x86_64 and arm64).
- [ ] No iOS-only APIs referenced (check with `#if TARGET_OS_TV` where needed).
- [ ] Public header unchanged (or change is intentional and approved).
