const std = @import("std");
const c = @import("clib.zig").c;

const Buffer = @import("buffer.zig").Buffer;
const ImVec2 = @import("vec.zig").ImVec2;
const WidgetCommand = @import("widget_command.zig").WidgetCommand;
const WidgetText = @import("widget_text.zig").WidgetText;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;

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
        _ = c.igSetNextWindowSize(ImVec2(@intToFloat(f32, self.window_size.a), @intToFloat(f32, self.window_size.b)), 0);
        _ = c.igBegin("EditorWindow", 1, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoMove);

        self.currentWidgetText().render(); // FIXME(remy): currentWidgetText should not be used or be better implemented
        c.igEnd();

        // command input
        if (self.focused_widget == FocusedWidget.Command) {
            _ = c.igSetNextWindowSize(ImVec2(@intToFloat(f32, self.window_size.a) / 2, @intToFloat(f32, 38)), 0);
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

    /// visibleLinesInWindow returns how many lines can be drawn on the window
    /// depending on the size of the window.
    fn visibleLinesInWindow(self: App) u64 {
        var rv: f32 = 0.0;
        switch (self.font_mode) {
            .LowDPI => rv = @intToFloat(f32, self.window_size.b) / self.font_lowdpi.FontSize,
            .LowDPIBigFont => rv = @intToFloat(f32, self.window_size.b) / self.font_lowdpibigfont.FontSize,
            .HiDPI => rv = @intToFloat(f32, self.window_size.b) / (self.font_hidpi.FontSize * 0.5),
        }
        return @floatToInt(u64, rv);
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
        var visible_lines_count = self.visibleLinesInWindow();
        for (self.editors.items) |editor, i| {
            self.editors.items[i].visible_lines = Vec2i{
                .a = editor.visible_lines.a,
                .b = editor.visible_lines.a + @intCast(i64, visible_lines_count),
            };
        }
    }

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

                // XXX(remy): will we have to get a "currently focused" widget?
                switch (event.type) {
                    c.SDL_KEYDOWN => {
                        switch (event.key.keysym.sym) {
                            c.SDLK_RETURN => {
                                // TODO(remy): implement
                            },
                            c.SDLK_ESCAPE => {
                                self.focused_widget = FocusedWidget.Command;
                            },
                            else => {},
                        }
                    },
                    c.SDL_WINDOWEVENT => {
                        if (event.window.event == c.SDL_WINDOWEVENT_SIZE_CHANGED) {
                            self.onWindowResized(event.window.data1, event.window.data2);
                        }
                    },
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
