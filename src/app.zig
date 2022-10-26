const std = @import("std");
const c = @import("clib.zig").c;

const Buffer = @import("buffer.zig").Buffer;
const ImVec2 = @import("vec.zig").ImVec2;
const WidgetCommand = @import("widget_command.zig").WidgetCommand;
const WidgetText = @import("widget_text.zig").WidgetText;
const Vec2i = @import("vec.zig").Vec2i;

// TODO(comment):
pub const App = struct {
    allocator: std.mem.Allocator,
    editors: std.ArrayList(WidgetText),
    command: WidgetCommand,
    gl_context: c.SDL_GLContext,
    imgui_context: *c.ImGuiContext,
    sdl_window: *c.SDL_Window,

    // TODO(remy): comment
    // TODO(remy): tests
    font_lowdpi: *c.ImFont,
    font_hidpi: *c.ImFont,
    hidpi: bool,

    // TODO(remy): comment
    is_running: bool,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !App {
        // SDL init

        if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
            std.log.err("sdl: can't c.SDL_Init(c.SDL_INIT_VIDEO)", .{});
        }

        // OpenGL init

        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_FLAGS, c.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_DOUBLEBUFFER, 1);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_DEPTH_SIZE, 24);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_STENCIL_SIZE, 8);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 2);

        // create the SDL Window

        var sdl_window = c.SDL_CreateWindow("meh", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 800, 800, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI);

        if (sdl_window == null) {
            // TODO(remy): return an error
        }

        // create the OpenGL context

        var gl_context = c.SDL_GL_CreateContext(sdl_window);
        _ = c.SDL_GL_MakeCurrent(sdl_window, gl_context);
        _ = c.SDL_GL_SetSwapInterval(1);

        // init imgui and its OpenGL/SDL2 backend

        var imgui_context = c.igCreateContext(null);

        _ = c.ImGui_ImplSDL2_InitForOpenGL(sdl_window, imgui_context);
        _ = c.ImGui_ImplOpenGL3_Init(null);

        // show and raise the window

        c.SDL_ShowWindow(sdl_window);
        c.SDL_RaiseWindow(sdl_window);

        // load the fonts

        var font_lowdpi = c.ImFontAtlas_AddFontFromFileTTF(c.igGetIO().*.Fonts, "res/UbuntuMono-Regular.ttf", 16, 0, 0);
        var font_hidpi = c.ImFontAtlas_AddFontFromFileTTF(c.igGetIO().*.Fonts, "res/UbuntuMono-Regular.ttf", 32, 0, 0);

        // return the created app
        return App{
            .allocator = allocator,
            .editors = std.ArrayList(WidgetText).init(allocator),
            .command = WidgetCommand.init(),
            .gl_context = gl_context,
            .imgui_context = imgui_context,
            .is_running = true,
            .sdl_window = sdl_window.?,
            .font_lowdpi = font_lowdpi,
            .font_hidpi = font_hidpi,
            .hidpi = false,
        };
    }

    pub fn deinit(self: *App) void {
        for (self.editors.item) |editor| {
            editor.deinit();
        }
        self.editors.deinit();

        c.ImGui_ImplOpenGL3_Shutdown();
        c.ImGui_ImplSDL2_Shutdown();

        c.igDestroyContext(self.imgui_context);
        self.imgui_context = null;

        c.SDL_GL_DeleteContext(self.gl_context);
        self.gl_context = null;

        c.SDL_DestroyWindow(self.sdl_window);
        self.sdl_window = null;

        c.SDL_Quit();
    }

    // Methods
    // TODO(remy): re-order the methods
    // -------

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn openFile(self: *App, filepath: []const u8) !void {
        var buffer = try Buffer.initFromFile(self.allocator, filepath);
        var editor = WidgetText.initWithBuffer(self.allocator, self, buffer);
        try self.editors.append(editor);
    }

    // FIXME(remy): this method isn't testing anything and will crash the
    // app if no file is opened.
    pub fn currentWidgetText(self: App) *WidgetText {
        return &self.editors.items[0];
    }

    fn render(self: *App) void {
        // prepare a new frame for rendering
        // -------

        _ = c.ImGui_ImplOpenGL3_NewFrame();
        c.ImGui_ImplSDL2_NewFrame();
        _ = c.igNewFrame();

        var w: c_int = 0;
        var h: c_int = 0;
        c.SDL_GetWindowSize(self.sdl_window, &w, &h);

        // detect if we've changed the monitor the window is on
        var gl_w: c_int = 0;
        var gl_h: c_int = 0;
        c.SDL_GL_GetDrawableSize(self.sdl_window, &gl_w, &gl_h);
        if (gl_w > w and gl_h > h and !self.hidpi) {
            self.setHdpi(true);
        } else if (gl_w == w and gl_h == h and self.hidpi) {
            self.setHdpi(false);
        }

        // render list
        // -----------

        // editor window
        _ = c.igSetNextWindowSize(ImVec2(@intToFloat(f32, w), @intToFloat(f32, h)), 0);
        _ = c.igBegin("EditorWindow", 1, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoMove);
        self.currentWidgetText().render(); // FIXME(remy): currentWidgetText should not be used or be better implemented
        c.igEnd();

        // command input
        _ = c.igSetNextWindowSize(ImVec2(@intToFloat(f32, w) / 2, @intToFloat(f32, 38)), 0);
        _ = c.igBegin("CommandWindow", 1, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoMove);
        if (c.igInputText("##command", &self.command.buff, @sizeOf(@TypeOf(self.command.buff)), c.ImGuiInputTextFlags_EnterReturnsTrue | c.ImGuiInputTextFlags_CallbackAlways, WidgetCommand.callback, null)) {
            self.command.interpret(self);
        }
        c.igEnd();

        // demo window
        // c.igShowDemoWindow(1);

        // rendering
        c.igRender();
        c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());
        c.SDL_GL_SwapWindow(self.sdl_window);

        c.SDL_Delay(16);
    }

    fn setHdpi(self: *App, enabled: bool) void {
        std.log.debug("App.setHdpi: {}", .{enabled});
        if (enabled) {
            self.hidpi = true;
            c.igGetIO().*.FontDefault = self.font_hidpi;
            c.igGetIO().*.FontGlobalScale = 0.5;
        } else {
            self.hidpi = false;
            c.igGetIO().*.FontDefault = self.font_lowdpi;
            c.igGetIO().*.FontGlobalScale = 1.0;
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn quit(self: *App) void {
        // TODO(remy): messagebox to save
        self.is_running = false;
    }

    pub fn mainloop(self: *App) !void {
        c.SDL_StartTextInput();
        var event: c.SDL_Event = undefined;
        self.is_running = true;

        while (self.is_running) {
            while (c.SDL_PollEvent(&event) > 0) {
                _ = c.ImGui_ImplSDL2_ProcessEvent(&event);

                if (event.type == c.SDL_QUIT) {
                    self.quit();
                    break;
                }

                // TODO(remy): we should be able too close the app from someone handling the events
                // XXX(remy): will we have to get a "currently focused" widget?
                switch (event.type) {
                    c.SDL_TEXTINPUT => {
                        _ = self.currentWidgetText().onTextInput(event.text.text[0]);
                    },
                    c.SDL_MOUSEWHEEL => {
                        if (event.wheel.y < 0) {
                            self.currentWidgetText().visible_lines.a += 3;
                            self.currentWidgetText().visible_lines.b += 3;
                        } else if (event.wheel.y > 0) {
                            self.currentWidgetText().visible_lines.a -= 3;
                            self.currentWidgetText().visible_lines.b -= 3;
                        }
                    },
                    else => {},
                }
            }

            self.render();
        }
    }
};
