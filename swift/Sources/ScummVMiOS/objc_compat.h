// Compatibility shim for package-level forced includes.
//
// This file is intentionally a no-op. Defining or remapping Objective-C
// YES/NO macros in Objective-C++ causes collisions with ScummVM symbols like
// DisposeAfterUse::YES / DisposeAfterUse::NO.
//
// Keep this header present so external/user build settings that still pass
// '-include objc_compat.h' do not fail with a missing file.
#ifndef SCUMMVM_KIT_OBJC_COMPAT_H
#define SCUMMVM_KIT_OBJC_COMPAT_H
#endif
