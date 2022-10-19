const std = @import("std");
const builtin = @import("builtin");
const c = @import("clib.zig").c;

const Buffer = @import("buffer.zig").Buffer;
const ImVec2 = @import("vec.zig").ImVec2;
const Editor = @import("widget_editor.zig").Editor;

pub fn main() !void {
    std.log.debug("here", .{});

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        std.log.err("sdl: can't c.SDL_Init(c.SDL_INIT_VIDEO)", .{});
    }

    var window = c.SDL_CreateWindow("meh", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 800, 800, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE);

    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_FLAGS, c.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_DOUBLEBUFFER, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_DEPTH_SIZE, 24);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_STENCIL_SIZE, 8);
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
    var editor = Editor.initWithBuffer(std.heap.page_allocator, buffer);
    errdefer editor.deinit();

    while (run) {
        while (c.SDL_PollEvent(&event) > 0) {
            _ = c.ImGui_ImplSDL2_ProcessEvent(&event);
            if (event.type == c.SDL_QUIT) {
                run = false;
                break;
            }
            // XXX(remy): delegate this to the editor?
            // XXX(remy): has to be removed from here anyway
            // XXX(remy): will we have to get a "currently focused" widget?
            if (event.type == c.SDL_MOUSEWHEEL) {
                if (event.wheel.y < 0) {
                    editor.visible_lines.a += 3;
                    editor.visible_lines.b += 3;
                } else if (event.wheel.y > 0) {
                    editor.visible_lines.a -= 3;
                    editor.visible_lines.b -= 3;
                }
            }
        }

        // prepare a new frame for rendering
        _ = c.ImGui_ImplOpenGL3_NewFrame();
        c.ImGui_ImplSDL2_NewFrame();
        _ = c.igNewFrame();

        var w: c_int = 0;
        var h: c_int = 0;
        c.SDL_GetWindowSize(window, &w, &h);

        // render list
        _ = c.igSetNextWindowSize(ImVec2(@intToFloat(f32, w), @intToFloat(f32, h)), 0);
        _ = c.igBegin("MainWindow", 1, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoMove);
        editor.render();
        c.igEnd();

        // rendering
        c.igRender();
        c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());
        c.SDL_GL_SwapWindow(window);

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
