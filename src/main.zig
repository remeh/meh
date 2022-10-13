const std = @import("std");

const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cDefine("CIMGUI_API", "extern \"C\" ");
    @cDefine("CIMGUI_USE_SDL", "1");
    @cDefine("CIMGUI_USE_OPENGL3", "1");

    @cInclude("SDL2/SDL.h");
    @cInclude("cimgui.h");
    @cInclude("cimgui_impl.h");
});

pub fn main() !void {
    std.log.debug("here", .{});

    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_WINDOW_RESIZABLE) < 0) {
        std.log.err("sdl: can't c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_WINDOW_RESIZABLE)", .{});
    }

    var window = c.SDL_CreateWindow("meh", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 480, c.SDL_WINDOW_OPENGL);

    var gl_context = c.SDL_GL_CreateContext(window);
    _ = c.SDL_GL_MakeCurrent(window, gl_context);
    _ = c.SDL_GL_SetSwapInterval(1);

    var ctx = c.igCreateContext(null);
    c.igSetCurrentContext(ctx);
    _ = c.igStyleColorsDark(null);

    _ = c.ImGui_ImplSDL2_InitForOpenGL(window, ctx);
    _ = c.ImGui_ImplOpenGL3_Init("#version 130");

    c.SDL_ShowWindow(window);
    c.SDL_RaiseWindow(window);

    c.SDL_PumpEvents();

    var i: u8 = 0;
    while (i < 5) : (i += 1) {
        _ = c.ImGui_ImplOpenGL3_NewFrame();
        c.ImGui_ImplSDL2_NewFrame();
        _ = c.igNewFrame();

        _ = c.igBegin("Window", 1, c.ImGuiWindowFlags_AlwaysAutoResize);
        c.igText("Hello using SDL2+OpenGL3+DearImGui from Zig \\o/");
        c.igEnd();

        c.igRender();
        c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());
        c.SDL_GL_SwapWindow(window);
        c.SDL_Delay(1000);
    }

    c.SDL_DestroyWindow(window);
    window = null;

    c.SDL_Quit();
}
