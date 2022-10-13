const std = @import("std");

const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cInclude("SDL2/SDL.h");
    @cDefine("CIMGUI_API", "extern \"C\" ");
    @cInclude("cimgui.h");
    @cDefine("CIMGUI_USE_SDL", "1");
    @cInclude("cimgui_impl.h");
});

pub fn main() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI) < 0) {
        std.log.err("c: can't SDL_Init(c.SDL_INIT_VIDEO)", .{});
    }

    var window = c.SDL_CreateWindow("meh", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 480, c.SDL_WINDOW_METAL);

    // _ = c._ImGui_ImplSDL2_Init(window, null, null);
    _ = c.ImGui_ImplSDL2_InitForOpenGL(window, null);

    var gl_context = c.SDL_GL_CreateContext(window);
    _ = c.SDL_GL_MakeCurrent(window, gl_context);
    _ = c.SDL_GL_SetSwapInterval(1);
    _ = c.igCreateContext(null);
    _ = c.igStyleColorsDark(null);

    c.SDL_ShowWindow(window);
    c.SDL_RaiseWindow(window);

    c.SDL_PumpEvents();
    c.SDL_Delay(3000);

    c.SDL_DestroyWindow(window);
    window = null;

    c.SDL_Quit();
}
