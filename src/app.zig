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

    editor_drawing_offset: Vec2u,

    // TODO(remy): comment
    window_pixel_size: Vec2u,
    // TODO(remy): comment
    window_scaled_size: Vec2u,
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
            .sdl_renderer = sdl_renderer.?,
            .is_running = true,
            .sdl_window = sdl_window.?,
            .font_lowdpi = font_lowdpi,
            .font_lowdpibigfont = font_lowdpibigfont,
            .font_hidpi = font_hidpi,
            .current_font = font_lowdpi,
            .font_mode = FontMode.LowDPI,
            .focused_widget = FocusedWidget.Editor,
            .window_pixel_size = window_size,
            .window_scaled_size = window_size,
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
        // grab screen information every render pass
        // -----------------------------------------

        self.refreshWindowPixelSize();
        self.refreshWindowScaledSize();
        self.refreshDPIMode();

        // render list
        // -----------

        // clean up between passes

        _ = c.SDL_SetRenderDrawColor(self.sdl_renderer, 30, 30, 30, 255);
        _ = c.SDL_RenderClear(self.sdl_renderer);

        // editor window

        var widget = &self.editors.items[0]; // FIXME(remy):
        widget.render(self.oneCharSize(), self.window_pixel_size, self.editor_drawing_offset);

        // command input TODO

        // rendering
        _ = c.SDL_RenderPresent(self.sdl_renderer);
    }

    fn setFontMode(self: *App, font_mode: FontMode) void {
        switch (font_mode) {
            .LowDPI => {
                self.current_font = self.font_lowdpi;
                self.editor_drawing_offset.a = 7 * 8; // 7 chars of width 8
                self.editor_drawing_offset.b = 27;
            },
            .LowDPIBigFont => {
                self.current_font = self.font_lowdpibigfont;
                self.editor_drawing_offset.a = 7 * 10; // 7 chars of width 10
                self.editor_drawing_offset.b = 27;
            },
            .HiDPI => {
                self.current_font = self.font_hidpi;
                self.editor_drawing_offset.a = @floatToInt(usize, (7 * (8 * self.window_scaling))); // 7 chars of width 8
                self.editor_drawing_offset.b = @floatToInt(usize, 27 * self.window_scaling);
            },
        }
        self.font_mode = font_mode;
    }

    /// refreshWindowPixelSize refreshes the window pixel size.
    fn refreshWindowPixelSize(self: *App) void {
        var gl_w: c_int = 0;
        var gl_h: c_int = 0;
        c.SDL_GL_GetDrawableSize(self.sdl_window, &gl_w, &gl_h);
        self.window_pixel_size.a = @intCast(usize, gl_w);
        self.window_pixel_size.b = @intCast(usize, gl_h);
    }

    /// refreshWindowScaledSize refreshes the window size (scaled).
    fn refreshWindowScaledSize(self: *App) void {
        var w: c_int = 0;
        var h: c_int = 0;
        c.SDL_GetWindowSize(self.sdl_window, &w, &h);
        self.window_scaled_size.a = @intCast(usize, w);
        self.window_scaled_size.b = @intCast(usize, h);
    }

    /// refreshDPIMode refreshes the DPI mode using the stored window pixel size
    /// and stored window scaled size.
    fn refreshDPIMode(self: *App) void {
        var display_index: c_int = c.SDL_GetWindowDisplayIndex(self.sdl_window);
        var desktop_resolution: c.SDL_DisplayMode = undefined;
        _ = c.SDL_GetDesktopDisplayMode(display_index, &desktop_resolution); // get the resolution

        if ((self.window_pixel_size.a > self.window_scaled_size.a and self.window_pixel_size.b > self.window_scaled_size.b and self.font_mode != FontMode.HiDPI)) {
            // hidpi
            self.window_scaling = @intToFloat(f32, self.window_pixel_size.a) / @intToFloat(f32, self.window_scaled_size.a);
            self.setFontMode(FontMode.HiDPI);
        } else if (self.window_scaled_size.a == self.window_pixel_size.a and self.window_scaled_size.b == self.window_pixel_size.b) {
            // lowdpi
            self.window_scaling = 1.0;
            if (desktop_resolution.h < 2000 and self.font_mode != FontMode.LowDPI) {
                self.setFontMode(FontMode.LowDPI);
            } else if (desktop_resolution.h > 2000 and self.font_mode != FontMode.LowDPIBigFont) {
                self.setFontMode(FontMode.LowDPIBigFont);
            }
        }
    }

    /// visibleColumnsAndLinesInWindow returns how many lines can be drawn on the window
    /// depending on the scaled size of the window.
    pub fn visibleColumnsAndLinesInWindow(self: App) Vec2u {
        var one_char_size = self.oneCharSize();
        var columns = (self.window_pixel_size.a - self.editor_drawing_offset.a) / @floatToInt(usize, @intToFloat(f32, one_char_size.a));
        var lines = (self.window_pixel_size.b - self.editor_drawing_offset.b) / @floatToInt(usize, @intToFloat(f32, one_char_size.b));

        return Vec2u{ .a = columns, .b = lines };
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
    fn onWindowResized(self: *App) void {
        self.refreshWindowPixelSize();
        self.refreshWindowScaledSize();

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

        // immediately trigger a first render pass for responsiveness
        self.onWindowResized();
        self.render();

        // mainloop
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
                            self.onWindowResized();
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
            rv.a = @floatToInt(usize, @intToFloat(f32, x) * self.window_scaling);
        }
        if (y < 0) {
            rv.b = 0;
        } else {
            rv.b = @floatToInt(usize, @intToFloat(f32, y) * self.window_scaling);
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
