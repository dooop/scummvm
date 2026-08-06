// Shim for the vorbisfile XCFramework's own vorbisfile.h, which does a bare
// #include "codec.h" expecting its usual sibling in the same directory (the
// upstream libvorbis layout ships codec.h and vorbisfile.h together under a
// single vorbis/ folder). Our vorbis and vorbisfile binaries are packaged as
// separate XCFrameworks, so that sibling lookup fails; forward to the real
// header in the vorbis XCFramework instead.
#include <vorbis/codec.h>
