const std = @import("std");
const c = @import("clib.zig").c;

const debugRect = @import("clib.zig").debugRect;

const Buffer = @import("buffer.zig").Buffer;
const ImVec2 = @import("vec.zig").ImVec2;
const WidgetCommand = @import("widget_command.zig").WidgetCommand;
const WidgetText = @import("widget_text.zig").WidgetText;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;

pub const FocusedWidget = enum {
    Editor,
    Command,
};

pub const FontMode = enum {
    LowDPI,
    LowDPIBigFont,
    HiDPI,
};

// TODO(comment):
// The app has three fonts mode:
//   * hidpi: using a bigger font but scaled by 0.5, providing the hidpi rendering quality
//   * lowdpi: using a normal font with no scale
//   * lowdpibigfont: using a normal font with no scale, but slightly bigger font than lowdpi
//                    for high resolutions (for the text to not look small).
pub const App = struct {
    allocator: std.mem.Allocator,
    command: WidgetCommand,
    editors: std.ArrayList(WidgetText),
    gl_context: c.SDL_GLContext,
    imgui_context: *c.ImGuiContext,
    sdl_window: *c.SDL_Window,

    /// window_size is refreshed right before a frame rendering,
    /// it means this value can be used as the source of truth of
    /// the current windows size.
    window_size: Vec2i,

    // TODO(remy): comment
    // TODO(remy): tests
    font_lowdpi: *c.ImFont,
    font_lowdpibigfont: *c.ImFont,
    font_hidpi: *c.ImFont,
    font_mode: FontMode,

    // TODO(remy): comment
    is_running: bool,

    // TODO(remy): comment
    focused_widget: FocusedWidget,

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

        var window_size = Vec2i{ .a = 800, .b = 800 };
        var sdl_window = c.SDL_CreateWindow(
            "meh",
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            @intCast(c_int, window_size.a),
            @intCast(c_int, window_size.b),
            c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI,
        );

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
        var font_lowdpibigfont = c.ImFontAtlas_AddFontFromFileTTF(c.igGetIO().*.Fonts, "res/UbuntuMono-Regular.ttf", 20, 0, 0);
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
            .font_lowdpibigfont = font_lowdpibigfont,
            .font_hidpi = font_hidpi,
            .focused_widget = FocusedWidget.Editor,
            .font_mode = FontMode.LowDPI,
            .window_size = window_size,
        };
    }

    pub fn deinit(self: *App) void {
        var i: usize = 0;
        while (i < self.editors.items.len) : (i += 1) {
            self.editors.items[i].deinit();
        }
        self.editors.deinit();

        c.ImGui_ImplOpenGL3_Shutdown();
        c.ImGui_ImplSDL2_Shutdown();

        c.igDestroyContext(self.imgui_context);
        self.imgui_context = undefined;

        c.SDL_GL_DeleteContext(self.gl_context);
        self.gl_context = undefined;

        c.SDL_DestroyWindow(self.sdl_window);
        self.sdl_window = undefined;

        c.SDL_Quit();

        std.log.debug("bye!", .{});
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

        var display_index: c_int = c.SDL_GetWindowDisplayIndex(self.sdl_window);
        var desktop_resolution: c.SDL_DisplayMode = undefined;
        _ = c.SDL_GetDesktopDisplayMode(display_index, &desktop_resolution); // get the resolution

        // detect if we've changed the monitor the window is on
        var gl_w: c_int = 0;
        var gl_h: c_int = 0;
        c.SDL_GL_GetDrawableSize(self.sdl_window, &gl_w, &gl_h);
        if ((gl_w > self.window_size.a and gl_h > self.window_size.b and self.font_mode != FontMode.HiDPI)) {
            self.setFontMode(FontMode.HiDPI);
        } else if (gl_w == self.window_size.a and gl_h == self.window_size.b and desktop_resolution.h < 2000 and self.font_mode != FontMode.LowDPI) {
            self.setFontMode(FontMode.LowDPI);
        } else if (desktop_resolution.h > 2000 and self.font_mode != FontMode.LowDPIBigFont) {
            self.setFontMode(FontMode.LowDPIBigFont);
        }

        // render list
        // -----------

        // editor window

        // no padding on the editor window
        c.igPushStyleVar_Vec2(c.ImGuiStyleVar_WindowPadding, c.ImVec2{ .x = 1.0, .y = 1.0 });
        c.igPushStyleVar_Float(c.ImGuiStyleVar_TabRounding, 3.0);
        _ = c.igSetNextWindowSize(ImVec2(@intToFloat(f32, self.window_size.a), @intToFloat(f32, self.window_size.b)), 0);
        _ = c.igBegin("EditorWindow", 1, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoMove);
        var open: bool = true;
        var filename: [8192]u8 = std.mem.zeroes([8192]u8);
        if (c.igBeginTabBar("##EditorTabs", c.ImGuiTabBarFlags_Reorderable)) {
            // TODO(remy): for (self.editors) |editor| blablabla
            std.mem.copy(u8, &filename, self.currentWidgetText().editor.buffer.filepath.bytes()); // TODO(remy): add random after ## (or full path?)
            if (c.igBeginTabItem(@ptrCast([*c]const u8, &filename), &open, c.ImGuiTabItemFlags_UnsavedDocument)) {
                self.currentWidgetText().render(); // FIXME(remy): currentWidgetText should not be used or be better implemented
                c.igEndTabItem();
            }
            c.igEndTabBar();
        }
        c.igEnd();
        c.igPopStyleVar(2);

        // command input
        if (self.focused_widget == FocusedWidget.Command) {
            _ = c.igSetNextWindowSize(ImVec2(@intToFloat(f32, self.window_size.a) * 0.8, @intToFloat(f32, 38)), 0);
            _ = c.igSetNextWindowFocus();
            _ = c.igBegin("CommandWindow", 1, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoMove);
            c.igSetKeyboardFocusHere(1);
            if (c.igInputText("##command", &self.command.buff, @sizeOf(@TypeOf(self.command.buff)), c.ImGuiInputTextFlags_EnterReturnsTrue | c.ImGuiInputTextFlags_CallbackAlways, WidgetCommand.callback, null)) {
                self.command.interpret(self);
            }
            c.igEnd();
        }

        // demo window
        // c.igShowDemoWindow(1);

        // rendering
        c.igRender();
        c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());
        c.SDL_GL_SwapWindow(self.sdl_window);

        c.SDL_Delay(16);
    }

    fn setFontMode(self: *App, font_mode: FontMode) void {
        std.log.debug("App.setHdpi: {}", .{font_mode});
        switch (font_mode) {
            .LowDPI => {
                c.igGetIO().*.FontDefault = self.font_lowdpi;
                c.igGetIO().*.FontGlobalScale = 1.0;
            },
            .LowDPIBigFont => {
                c.igGetIO().*.FontDefault = self.font_lowdpibigfont;
                c.igGetIO().*.FontGlobalScale = 1.0;
            },
            .HiDPI => {
                c.igGetIO().*.FontDefault = self.font_hidpi;
                c.igGetIO().*.FontGlobalScale = 0.5;
            },
        }
        self.font_mode = font_mode;
    }

    /// visibleColumnsAndLinesInWindow returns how many lines can be drawn on the window
    /// depending on the size of the window.
    fn visibleColumnsAndLinesInWindow(self: App) Vec2u {
        var one_char_size = self.oneCharSize();
        var columns: f32 = @intToFloat(f32, self.window_size.a) / one_char_size.a;
        var lines: f32 = @intToFloat(f32, self.window_size.b) / one_char_size.b;
        return Vec2u{
            .a = @floatToInt(u64, @ceil(columns)),
            .b = @floatToInt(u64, @ceil(lines)),
        };
    }

    /// oneCharSize returns the bounding box of one text char.
    pub fn oneCharSize(_: App) Vec2f {
        var v = ImVec2(0, 0);
        c.igCalcTextSize(&v, "0", null, false, 0.0);
        return Vec2f{ .a = v.x, .b = v.y };
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn quit(self: *App) void {
        // TODO(remy): messagebox to save
        self.is_running = false;
    }

    /// onWindowResized is called when the windows has just been resized.
    fn onWindowResized(self: *App, w: i32, h: i32) void {
        self.window_size.a = w;
        self.window_size.b = h;

        // change visible lines of every WidgetText
        var visible_count = self.visibleColumnsAndLinesInWindow();
        for (self.editors.items) |editor, i| {
            self.editors.items[i].viewport.lines = Vec2u{
                .a = editor.viewport.lines.a,
                .b = editor.viewport.lines.a + visible_count.b,
            };
            self.editors.items[i].viewport.columns = Vec2u{
                .a = editor.viewport.columns.a,
                .b = editor.viewport.columns.a + visible_count.a,
            };
        }
    }

    /// mainloop of the application.
    pub fn mainloop(self: *App) !void {
        c.SDL_StartTextInput(); // TODO(remy): do this only if current focus is the widget_text
        var event: c.SDL_Event = undefined;
        self.is_running = true;
        while (self.is_running) {
            while (c.SDL_PollEvent(&event) > 0) {
                _ = c.ImGui_ImplSDL2_ProcessEvent(&event);

                if (event.type == c.SDL_QUIT) {
                    self.quit();
                    break;
                }

                // events to handle independently of the currently focused widget
                switch (event.type) {
                    c.SDL_WINDOWEVENT => {
                        if (event.window.event == c.SDL_WINDOWEVENT_SIZE_CHANGED) {
                            self.onWindowResized(event.window.data1, event.window.data2);
                        }
                    },
                    else => {},
                }

                // events to handle differently per focused widget
                switch (self.focused_widget) {
                    .Command => {
                        self.commandEvents(event);
                    },
                    .Editor => {
                        self.editorEvents(event);
                    },
                }
            }

            self.render();
        }
    }

    fn commandEvents(self: *App, event: c.SDL_Event) void {
        switch (event.type) {
            c.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    c.SDLK_ESCAPE => {
                        self.focused_widget = FocusedWidget.Editor;
                        self.command.reset();
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    fn editorEvents(self: *App, event: c.SDL_Event) void {
        var input_state = c.SDL_GetKeyboardState(null);
        var ctrl: bool = input_state[c.SDL_SCANCODE_LCTRL] == 1 or input_state[c.SDL_SCANCODE_RCTRL] == 1;
        switch (event.type) {
            c.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    c.SDLK_RETURN => {
                        self.currentWidgetText().onReturn();
                    },
                    c.SDLK_ESCAPE => {
                        // if the onEscape isn't absorbed by the WidgetText,
                        // we will want to change the focus on widgets.
                        if (!self.currentWidgetText().onEscape()) {
                            self.focused_widget = FocusedWidget.Command;
                        }
                    },
                    c.SDLK_BACKSPACE => {
                        self.currentWidgetText().onBackspace();
                    },
                    else => {
                        if (ctrl) {
                            _ = self.currentWidgetText().onCtrlKeyDown(event.key.keysym.sym);
                        }
                    },
                }
            },
            c.SDL_TEXTINPUT => {
                _ = self.currentWidgetText().onTextInput(readTextFromSDLInput(&event.text.text));
            },
            c.SDL_MOUSEWHEEL => {
                _ = self.currentWidgetText().onMouseWheel(Vec2i{ .a = event.wheel.x, .b = event.wheel.y });
            },
            else => {},
        }
    }

    fn readTextFromSDLInput(sdl_text_input: []const u8) []const u8 {
        var i: usize = 0;
        while (i < sdl_text_input.len) : (i += 1) {
            if (sdl_text_input[i] == 0) {
                return sdl_text_input[0..i];
            }
        }
        return sdl_text_input[0..sdl_text_input.len];
    }
};
