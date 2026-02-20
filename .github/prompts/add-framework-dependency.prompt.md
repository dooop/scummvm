# Skill: Add a prebuilt XCFramework dependency

Use this skill when a new prebuilt library needs to be linked into the
`ScummVMEngine` target.

## Prerequisites
- The `.xcframework` bundle is available and covers all required slices:
  - `ios-arm64` (device)
  - `ios-x86_64-arm64-simulator` (simulator)
  - `macos-arm64`
  - `tvos-arm64` (device)
  - `tvos-x86_64-arm64-simulator` (simulator)

## Step 1: Place the framework

Copy the `.xcframework` bundle into `Frameworks/`:
```
Frameworks/<name>.xcframework/
```

Verify the expected slice directories are present under it.

## Step 2: Declare the binary target in Package.swift

Add a `.binaryTarget` entry in the `targets:` array. Use a local path — no URL
or checksum needed for local xcframeworks:

```swift
.binaryTarget(
    name: "<name>",
    path: "Frameworks/<name>.xcframework"
),
```

The `name` string becomes the import name used in the dependency list.

## Step 3: Add to ScummVMEngine dependencies

In the `ScummVMEngine` target's `dependencies:` array, add the name:

```swift
"<name>",
```

Follow the existing alphabetical ordering where possible.

## Step 4: Conditional linking (if platform-specific)

If the library is only available or required on some platforms, use a condition:

```swift
.target(name: "<name>", condition: .when(platforms: [.iOS, .tvOS])),
```

## Step 5: Verify

- `Package.swift` resolves without errors (`swift package dump-package`).
- The engine target links the new framework on all intended platforms.
- No duplicate symbol errors arise from the new library overlapping with
  another framework already in `Frameworks/`.

## Rules
- Never add source files alongside the xcframework — it is binary-only.
- Do not add xcframeworks that are already covered by the OS SDK.
- Keep `Frameworks/` sorted alphabetically for readability.
