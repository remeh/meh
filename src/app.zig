const std = @import("std");
const c = @import("clib.zig").c;

const Buffer = @import("buffer.zig").Buffer;
const Editor = @import("widget_editor.zig").Editor;
const ImVec2 = @import("vec.zig").ImVec2;
const Vec2i = @import("vec.zig").Vec2i;

// TODO(comment):
pub const App = struct {
    allocator: std.mem.Allocator,
    editors: std.ArrayList(Editor),

    gl_context: c.SDL_GLContext,
    imgui_context: *c.ImGuiContext,
    sdl_window: *c.SDL_Window,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !App {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
            std.log.err("sdl: can't c.SDL_Init(c.SDL_INIT_VIDEO)", .{});
        }

        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_FLAGS, c.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_DOUBLEBUFFER, 1);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_DEPTH_SIZE, 24);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_STENCIL_SIZE, 8);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 2);

        var sdl_window = c.SDL_CreateWindow("meh", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 800, 800, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI);

        if (sdl_window == null) {
            // TODO(remy): return an error
        }

        var gl_context = c.SDL_GL_CreateContext(sdl_window);
        _ = c.SDL_GL_MakeCurrent(sdl_window, gl_context);
        _ = c.SDL_GL_SetSwapInterval(1);

        var imgui_context = c.igCreateContext(null);

        _ = c.ImGui_ImplSDL2_InitForOpenGL(sdl_window, imgui_context);
        _ = c.ImGui_ImplOpenGL3_Init(null);

        c.SDL_ShowWindow(sdl_window);
        c.SDL_RaiseWindow(sdl_window);

        return App{
            .allocator = allocator,
            .editors = std.ArrayList(Editor).init(allocator),
            .gl_context = gl_context,
            .imgui_context = imgui_context,
            .sdl_window = sdl_window.?,
        };
    }

    pub fn deinit(self: *App) void {
        c.ImGui_ImplOpenGL3_Shutdown();
        c.ImGui_ImplSDL2_Shutdown();
        c.igDestroyContext(self.imgui_context);
        self.imgui_context = null;
        c.SDL_GL_DeleteContext(self.gl_context);
        self.gl_context = null;
        c.SDL_DestroyWindow(self.sdl_window);
        self.sdl_window = null;

        c.SDL_Quit();

        for (self.editors.item) |editor| {
            editor.deinit();
        }
        self.editors.deinit();
    }

    // Methods
    // -------

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn openFile(self: *App, filepath: []const u8) !void {
        var buffer = try Buffer.initFromFile(self.allocator, filepath);
        var editor = Editor.initWithBuffer(self.allocator, buffer);
        try self.editors.append(editor);
    }

    // FIXME(remy): this method isn't testing anything and will crash the
    // app if no file is opened.
    pub fn currentEditor(self: App) *Editor {
        return &self.editors.items[0];
    }

    pub fn mainloop(self: App) !void {
        c.SDL_StartTextInput();
        var event: c.SDL_Event = undefined;
        var run: bool = true;

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
                switch (event.type) {
                    c.SDL_TEXTINPUT => {
                        switch (event.text.text[0]) {
                            'q' => run = false,
                            'h' => self.currentEditor().moveCursor(Vec2i{ .a = -1, .b = 0 }),
                            'j' => self.currentEditor().moveCursor(Vec2i{ .a = 0, .b = 1 }),
                            'k' => self.currentEditor().moveCursor(Vec2i{ .a = 0, .b = -1 }),
                            'l' => self.currentEditor().moveCursor(Vec2i{ .a = 1, .b = 0 }),
                            'i' => self.currentEditor().input_mode = .Insert, // TODO(remy): remove
                            'r' => self.currentEditor().input_mode = .Replace, // TODO(remy): remove
                            else => {},
                        }
                    },
                    c.SDL_MOUSEWHEEL => {
                        if (event.wheel.y < 0) {
                            self.currentEditor().visible_lines.a += 3;
                            self.currentEditor().visible_lines.b += 3;
                        } else if (event.wheel.y > 0) {
                            self.currentEditor().visible_lines.a -= 3;
                            self.currentEditor().visible_lines.b -= 3;
                        }
                    },
                    else => {},
                }
            }

            // prepare a new frame for rendering
            _ = c.ImGui_ImplOpenGL3_NewFrame();
            c.ImGui_ImplSDL2_NewFrame();
            _ = c.igNewFrame();

            var w: c_int = 0;
            var h: c_int = 0;
            c.SDL_GetWindowSize(self.sdl_window, &w, &h);

            // render list
            _ = c.igSetNextWindowSize(ImVec2(@intToFloat(f32, w), @intToFloat(f32, h)), 0);
            _ = c.igBegin("MainWindow", 1, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoMove);
            self.currentEditor().render();
            c.igEnd();

            // rendering
            c.igRender();
            c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());
            c.SDL_GL_SwapWindow(self.sdl_window);

            c.SDL_Delay(16);
        }
    }
};
