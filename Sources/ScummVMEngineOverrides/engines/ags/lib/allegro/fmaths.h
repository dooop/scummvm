/* ScummVM - Graphic Adventure Engine
 *
 * Override header to ensure Allegro macros are available without touching
 * the upstream submodule.
 */

#ifndef AGS_LIB_ALLEGRO_FMATHS_H
#define AGS_LIB_ALLEGRO_FMATHS_H

#include "ags/lib/allegro/alconfig.h"
#include "ags/lib/allegro/fixed.h"

namespace AGS3 {

AL_FUNC(fixed, fixsqrt, (fixed x));
AL_FUNC(fixed, fixhypot, (fixed x, fixed y));
AL_FUNC(fixed, fixatan, (fixed x));
AL_FUNC(fixed, fixatan2, (fixed y, fixed x));

AL_ARRAY(const fixed, _cos_tbl);
AL_ARRAY(const fixed, _tan_tbl);
AL_ARRAY(const fixed, _acos_tbl);

} // namespace AGS3

#endif
