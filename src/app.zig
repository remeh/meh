const std = @import("std");
const c = @import("clib.zig").c;

const debugRect = @import("clib.zig").debugRect;

const Buffer = @import("buffer.zig").Buffer;
const ImVec2 = @import("vec.zig").ImVec2;
const Font = @import("font.zig").Font;
const WidgetCommand = @import("widget_command.zig").WidgetCommand;
const WidgetText = @import("widget_text.zig").WidgetText;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;

pub const AppError = error{
    CantInit,
};

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
    // gl_context: c.SDL_GLContext,
    sdl_window: *c.SDL_Window,
    sdl_renderer: *c.SDL_Renderer,
    /// first_render is used to computes and validates a few things (window size, font sizes)
    /// once the first frame has been rendered.
    first_render: bool,

    editor_drawing_offset: Vec2u,

    /// window_size is refreshed right before a frame rendering,
    /// it means this value can be used as the source of truth of
    /// the current windows size.
    window_size: Vec2u,
    /// window_scaling contains the scale between the actual GL rendered
    /// surface and the window size.
    window_scaling: f32,

    // TODO(remy): comment
    // TODO(remy): tests
    font_lowdpi: Font,
    font_lowdpibigfont: Font,
    font_hidpi: Font,
    current_font: Font,
    font_mode: FontMode,

    /// mainloop is running flag.
    is_running: bool,

    // TODO(remy): comment
    current_widget_text_tab: usize,
    focused_widget: FocusedWidget,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !App {
        // SDL init

        if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
            std.log.err("sdl: can't c.SDL_Init(c.SDL_INIT_VIDEO)", .{});
        }

        if (c.TTF_Init() < 0) {
            std.log.err("sdl: can't c.TTF_Init()", .{});
        }

        // OpenGL init

        // _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_FLAGS, c.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
        // _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
        // _ = c.SDL_GL_SetAttribute(c.SDL_GL_DOUBLEBUFFER, 1);
        // _ = c.SDL_GL_SetAttribute(c.SDL_GL_DEPTH_SIZE, 24);
        // _ = c.SDL_GL_SetAttribute(c.SDL_GL_STENCIL_SIZE, 8);
        // _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        // _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 2);

        // create the SDL Window

        var window_size = Vec2u{ .a = 800, .b = 800 };
        var sdl_window = c.SDL_CreateWindow(
            "meh",
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            @intCast(c_int, window_size.a),
            @intCast(c_int, window_size.b),
            c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI,
        );

        if (sdl_window == null) {
            std.log.err("App.init: can't create SDL window.", .{});
            return AppError.CantInit;
        }

        // create the OpenGL context and SDL renderer
        // var gl_context = c.SDL_GL_CreateContext(sdl_window);
        // _ = c.SDL_GL_MakeCurrent(sdl_window, gl_context);
        // _ = c.SDL_GL_SetSwapInterval(1);

        var sdl_renderer: ?*c.SDL_Renderer = c.SDL_CreateRenderer(sdl_window, -1, c.SDL_RENDERER_ACCELERATED);
        if (sdl_renderer == null) {
            std.log.err("App.init: can't create an SDL Renderer.", .{});
            return AppError.CantInit;
        }

        _ = c.SDL_SetRenderDrawBlendMode(sdl_renderer, c.SDL_BLENDMODE_BLEND);

        // show and raise the window

        c.SDL_ShowWindow(sdl_window);
        c.SDL_RaiseWindow(sdl_window);

        // load the fonts

        var font_lowdpi = try Font.init(allocator, sdl_renderer.?, "./res/UbuntuMono-Regular.ttf", 18);
        var font_lowdpibigfont = try Font.init(allocator, sdl_renderer.?, "./res/UbuntuMono-Regular.ttf", 22);
        var font_hidpi = try Font.init(allocator, sdl_renderer.?, "./res/UbuntuMono-Regular.ttf", 32);

        // return the created app
        return App{
            .allocator = allocator,
            .editor_drawing_offset = Vec2u{ .a = 64, .b = 27 },
            .editors = std.ArrayList(WidgetText).init(allocator),
            .command = WidgetCommand.init(),
            .current_widget_text_tab = 0,
            // .gl_context = gl_context,
            .sdl_renderer = sdl_renderer.?,
            .is_running = true,
            .sdl_window = sdl_window.?,
            .first_render = true,
            .font_lowdpi = font_lowdpi,
            .font_lowdpibigfont = font_lowdpibigfont,
            .font_hidpi = font_hidpi,
            .current_font = font_lowdpi,
            .font_mode = FontMode.LowDPI,
            .focused_widget = FocusedWidget.Editor,
            .window_size = window_size,
            .window_scaling = 1.0,
        };
    }

    pub fn deinit(self: *App) void {
        var i: usize = 0;
        while (i < self.editors.items.len) : (i += 1) {
            self.editors.items[i].deinit();
        }
        self.editors.deinit();

        self.font_lowdpi.deinit();
        self.font_lowdpibigfont.deinit();
        self.font_hidpi.deinit();

        c.SDL_DestroyRenderer(self.sdl_renderer);
        self.sdl_renderer = undefined;

        // c.SDL_GL_DeleteContext(self.gl_context);
        // self.gl_context = undefined;

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
        var editor = WidgetText.initWithBuffer(self.allocator, self, buffer, self.visibleColumnsAndLinesInWindow());
        try self.editors.append(editor);
    }

    // FIXME(remy): this method isn't testing anything and will crash the
    // app if no file is opened.
    pub fn currentWidgetText(self: App) *WidgetText {
        return &self.editors.items[self.current_widget_text_tab];
    }

    fn render(self: *App) void {
        var display_index: c_int = c.SDL_GetWindowDisplayIndex(self.sdl_window);
        var desktop_resolution: c.SDL_DisplayMode = undefined;
        _ = c.SDL_GetDesktopDisplayMode(display_index, &desktop_resolution); // get the resolution

        // detect if we've changed the monitor the window is on
        var gl_w: c_int = 0;
        var gl_h: c_int = 0;
        c.SDL_GL_GetDrawableSize(self.sdl_window, &gl_w, &gl_h);
        if ((gl_w > self.window_size.a and gl_h > self.window_size.b and self.font_mode != FontMode.HiDPI)) {
            self.setFontMode(FontMode.HiDPI);
            self.window_scaling = @intToFloat(f32, self.window_size.a) / @intToFloat(f32, gl_w);
        } else if (gl_w == self.window_size.a and gl_h == self.window_size.b and desktop_resolution.h < 2000 and self.font_mode != FontMode.LowDPI) {
            self.setFontMode(FontMode.LowDPI);
            self.window_scaling = 1.0;
        } else if (desktop_resolution.h > 2000 and self.font_mode != FontMode.LowDPIBigFont) {
            self.setFontMode(FontMode.LowDPIBigFont);
            self.window_scaling = 1.0;
        }

        // render list
        // -----------

        // clean up

        _ = c.SDL_SetRenderDrawColor(self.sdl_renderer, 30, 30, 30, 255);
        _ = c.SDL_RenderClear(self.sdl_renderer);

        // editor window

        var widget = &self.editors.items[0]; // FIXME(remy):
        widget.render(self.oneCharSize(), self.window_size, self.editor_drawing_offset);

        // command input

        // TODO(remy):

        // rendering
        // c.SDL_GL_SwapWindow(self.sdl_window);

        _ = c.SDL_RenderPresent(self.sdl_renderer);

        // FIXME(remy): added this to see if that's fixing the bug on gnome3
        if (self.first_render) {
            var w: c_int = undefined;
            var h: c_int = undefined;
            c.SDL_GetWindowSize(self.sdl_window, &w, &h);
            self.window_size.a = @intCast(usize, w);
            self.window_size.b = @intCast(usize, h);
            self.onWindowResized(self.window_size.a, self.window_size.b);
            self.first_render = false;
        }
    }

    fn setFontMode(self: *App, font_mode: FontMode) void {
        switch (font_mode) {
            .LowDPI => {
                self.editor_drawing_offset.a = 7 * 8; // 7 chars of width 8
                self.current_font = self.font_lowdpi;
            },
            .LowDPIBigFont => {
                self.editor_drawing_offset.a = 7 * 10; // 7 chars of width 10
                self.current_font = self.font_lowdpibigfont;
            },
            .HiDPI => {
                self.editor_drawing_offset.a = 7 * 8; // 7 chars of width 8
                self.current_font = self.font_hidpi;
            },
        }
        self.font_mode = font_mode;
    }

    /// visibleColumnsAndLinesInWindow returns how many lines can be drawn on the window
    /// depending on the size of the window.
    pub fn visibleColumnsAndLinesInWindow(self: App) Vec2u {
        // If no frame has been rendered, we can't compute the oneCharSize(),
        // meanwhile, return some values.
        if (self.first_render) {
            return Vec2u{ .a = 100, .b = 50 };
        }

        var one_char_size = self.oneCharSize();
        var columns = (self.window_size.a - self.editor_drawing_offset.a) / @floatToInt(usize, @intToFloat(f32, one_char_size.a) * self.window_scaling);
        var lines = (self.window_size.b - self.editor_drawing_offset.b) / @floatToInt(usize, @intToFloat(f32, one_char_size.b) * self.window_scaling);

        return Vec2u{
            .a = columns,
            .b = lines,
        };
    }

    /// oneCharSize returns the bounding box of one text char.
    pub fn oneCharSize(self: App) Vec2u {
        return Vec2u{
            .a = self.current_font.font_size / 2,
            .b = self.current_font.font_size,
        };
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn quit(self: *App) void {
        // TODO(remy): messagebox to save
        self.is_running = false;
    }

    /// onWindowResized is called when the windows has just been resized.
    fn onWindowResized(self: *App, w: usize, h: usize) void {
        self.window_size.a = w;
        self.window_size.b = h;

        std.log.debug("onWindowResized: {d}x{d}", .{ w, h });

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
        var event: c.SDL_Event = undefined;
        self.is_running = true;
        var to_render = true;
        c.SDL_StartTextInput(); // TODO(remy): do this only if current focus is the widget_text

        const frame_per_second = 60;
        const max_ms_skip = 1000 / frame_per_second;
        var start = std.time.milliTimestamp();
        var focused_widget = self.focused_widget;

        while (self.is_running) {
            start = std.time.milliTimestamp();

            // events handling
            // ---------------
            while (c.SDL_PollEvent(&event) > 0) {
                if (event.type == c.SDL_QUIT) {
                    self.quit();
                    break;
                }

                // events to handle independently of the currently focused widget
                switch (event.type) {
                    c.SDL_WINDOWEVENT => {
                        if (event.window.event == c.SDL_WINDOWEVENT_SIZE_CHANGED) {
                            self.onWindowResized(@intCast(usize, event.window.data1), @intCast(usize, event.window.data2));
                        }
                    },
                    else => {},
                }

                // events to handle differently per focused widget
                focused_widget = self.focused_widget;
                switch (self.focused_widget) {
                    .Command => {
                        self.commandEvents(event);
                        to_render = true;
                    },
                    .Editor => {
                        self.editorEvents(event);
                        to_render = true;
                    },
                }

                // the focus widget changed, trigger an immedate repaint
                if (self.focused_widget != focused_widget) {
                    self.render();
                    focused_widget = self.focused_widget;
                }
            }

            // rendering
            // ---------

            if (to_render) {
                self.render();
                to_render = false;
            }

            var max_sleep_ms = max_ms_skip - (std.time.milliTimestamp() - start);
            if (max_sleep_ms < 0) {
                max_sleep_ms = 0;
            }
            std.time.sleep(@intCast(u64, max_sleep_ms * std.time.ns_per_ms));
        }

        c.SDL_StopTextInput();
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
        var shift: bool = input_state[c.SDL_SCANCODE_LSHIFT] == 1 or input_state[c.SDL_SCANCODE_RSHIFT] == 1;
        var cmd: bool = input_state[c.SDL_SCANCODE_LGUI] == 1 or input_state[c.SDL_SCANCODE_RGUI] == 1;
        switch (event.type) {
            c.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    c.SDLK_RETURN => {
                        self.currentWidgetText().onReturn();
                    },
                    c.SDLK_ESCAPE => _ = self.currentWidgetText().onEscape(),
                    c.SDLK_COLON => {
                        if (self.currentWidgetText().input_mode == .Command) {
                            self.focused_widget = FocusedWidget.Command;
                        }
                        // TODO(remy):    self.command.buff[0] = ':';
                    },
                    c.SDLK_BACKSPACE => {
                        self.currentWidgetText().onBackspace();
                    },
                    c.SDLK_TAB => {
                        self.currentWidgetText().onTab(shift); // TODO(remy): support shift-tab
                    },
                    else => {
                        if (ctrl) {
                            _ = self.currentWidgetText().onCtrlKeyDown(event.key.keysym.sym, ctrl, cmd);
                        }
                    },
                }
            },
            c.SDL_TEXTINPUT => {
                _ = self.currentWidgetText().onTextInput(readTextFromSDLInput(&event.text.text));
            },
            c.SDL_MOUSEWHEEL => {
                _ = self.currentWidgetText().onMouseWheel(Vec2i{ .a = event.wheel.x, .b = event.wheel.y }, self.visibleColumnsAndLinesInWindow());
            },
            c.SDL_MOUSEMOTION => {
                self.currentWidgetText().onMouseMove(self.sdlMousePosToVec2u(event.motion.x, event.motion.y), self.editor_drawing_offset);
            },
            c.SDL_MOUSEBUTTONDOWN => {
                self.currentWidgetText().onMouseStartSelection(self.sdlMousePosToVec2u(event.button.x, event.button.y), self.editor_drawing_offset);
            },
            c.SDL_MOUSEBUTTONUP => {
                self.currentWidgetText().onMouseStopSelection(self.sdlMousePosToVec2u(event.button.x, event.button.y), self.editor_drawing_offset);
            },
            else => {},
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    fn sdlMousePosToVec2u(self: App, x: c_int, y: c_int) Vec2u {
        var rv = Vec2u{ .a = 0, .b = 0 };
        if (x < 0) {
            rv.a = 0;
        } else {
            rv.a = @floatToInt(usize, @intToFloat(f32, x) / self.window_scaling);
        }
        if (y < 0) {
            rv.b = 0;
        } else {
            rv.b = @floatToInt(usize, @intToFloat(f32, y) / self.window_scaling);
        }
        return rv;
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
