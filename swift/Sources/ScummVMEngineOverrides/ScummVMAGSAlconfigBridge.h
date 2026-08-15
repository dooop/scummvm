#pragma once

// SwiftPM also compiles generated Objective-C sources for resource bundles.
// Keep the AGS preinclude as C++-only so Objective-C compilation does not
// choke on C++ namespace declarations in alconfig.h.
#ifdef __cplusplus
#include "engines/ags/lib/allegro/alconfig.h"
#endif
