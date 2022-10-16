const std = @import("std");
const builtin = @import("builtin");

const Buffer = @import("buffer.zig").Buffer;

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

    var window = c.SDL_CreateWindow("meh", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 800, 800, c.SDL_WINDOW_OPENGL);

    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_FLAGS, c.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG); // Always required on Mac
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 2);

    var gl_context = c.SDL_GL_CreateContext(window);
    _ = c.SDL_GL_MakeCurrent(window, gl_context);
    _ = c.SDL_GL_SetSwapInterval(1);

    var context = c.igCreateContext(null);
    c.igSetCurrentContext(context);

    _ = c.ImGui_ImplSDL2_InitForOpenGL(window, context);

    if (builtin.os.tag == .macos) {
        _ = c.ImGui_ImplOpenGL3_Init("#version 150");
    } else {
        // TODO(remy): what about selecting this on Linux?
        _ = c.ImGui_ImplOpenGL3_Init("#version 130");
    }

    c.SDL_ShowWindow(window);
    c.SDL_RaiseWindow(window);

    var event: c.SDL_Event = undefined;
    var run: bool = true;

    var buffer = try Buffer.initFromFile(std.heap.page_allocator, "src/main.zig");
    std.log.debug("{any}", .{buffer.getLinePos(1)});

    while (run) {
        while (c.SDL_PollEvent(&event) > 0) {
            _ = c.ImGui_ImplSDL2_ProcessEvent(&event);
            if (event.type == c.SDL_QUIT) {
                run = false;
            }

            _ = c.ImGui_ImplOpenGL3_NewFrame();
            c.ImGui_ImplSDL2_NewFrame();
            _ = c.igNewFrame();

            // start drawing (test comment 😊)

            // var viewport = c.igGetMainViewport();
            // c.igSetNextWindowPos(viewport.*.WorkPos);

            _ = c.igSetNextWindowSize(imvec2(600, 800), 0);
            _ = c.igBegin("Window", 1, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoResize);
            c.igText("Hello using SDL2+OpenGL3+DearImGui from Zig \\o/");
            _ = c.igInputTextMultiline("##", @ptrCast([*:0]u8, buffer.data.items), buffer.data.items.len, imvec2(600, 600), 0, null, null);
            _ = c.igButton("Click Me!", imvec2(250, 50));
            c.igEnd();

            c.igShowDemoWindow(1);

            c.igRender();
            c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());
            c.SDL_GL_SwapWindow(window);
        }
        c.SDL_Delay(16);
    }

    // clean resources

    buffer.deinit();

    c.ImGui_ImplOpenGL3_Shutdown();
    c.ImGui_ImplSDL2_Shutdown();
    c.igDestroyContext(context);

    c.SDL_GL_DeleteContext(gl_context);
    c.SDL_DestroyWindow(window);
    window = null;

    c.SDL_Quit();
}

pub fn imvec2(x: f32, y: f32) c.ImVec2 {
    return c.ImVec2_ImVec2_Float(x, y).*;
}
