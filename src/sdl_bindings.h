// C source file used to generate Zig bindings for SDL2 and SDL2_ttf via
// `zig translate-c` (the `translate_c` build step).
//
// SDL_DISABLE_ARM_NEON_H avoids pulling in <arm_neon.h> which the Aro-based
// translate-c currently cannot parse on aarch64.
#define SDL_DISABLE_ARM_NEON_H
// SDL_DISABLE_IMMINTRIN_H avoids pulling in <immintrin.h> (via SDL_ttf.h ->
// SDL.h -> SDL_cpuinfo.h). The bundled clang headers' AVX intrinsics use
// builtins that the Aro-based translate-c cannot translate. SDL_ttf.h does not
// need these CPU intrinsics; the function declarations we use don't involve
// them.
#define SDL_DISABLE_IMMINTRIN_H
#define SDL_DISABLE_MMINTRIN_H
#define SDL_DISABLE_XMMINTRIN_H
#define SDL_DISABLE_EMMINTRIN_H
#define SDL_DISABLE_PMMINTRIN_H

#include "SDL2/SDL_stdinc.h"
#include "SDL2/SDL_error.h"
#include "SDL2/SDL_bits.h"
#include "SDL2/SDL_endian.h"
#include "SDL2/SDL_pixels.h"
#include "SDL2/SDL_rwops.h"
#include "SDL2/SDL_blendmode.h"
#include "SDL2/SDL_rect.h"
#include "SDL2/SDL_events.h"
#include "SDL2/SDL_keyboard.h"
#include "SDL2/SDL_keycode.h"
#include "SDL2/SDL_mouse.h"
#include "SDL2/SDL_video.h"
#include "SDL2/SDL_surface.h"
#include "SDL2/SDL_render.h"
#include "SDL2/SDL_clipboard.h"
#include "SDL2/SDL_ttf.h"
