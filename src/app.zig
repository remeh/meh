const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const Buffer = @import("buffer.zig").Buffer;

const ImVec2 = @import("vec.zig").ImVec2;
const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const WidgetCommand = @import("widget_command.zig").WidgetCommand;
const WidgetTextEdit = @import("widget_text_edit.zig").WidgetTextEdit;

const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const itou = @import("vec.zig").itou;

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

/// Main app structure.
/// The app has three fonts mode:
///   * hidpi: using a bigger font but scaled by 0.5, providing the hidpi rendering quality
///   * lowdpi: using a normal font with no scale
///   * lowdpibigfont: using a normal font with no scale, but slightly bigger font than lowdpi
///                    for high resolutions (for the text to not look small).
pub const App = struct {
    allocator: std.mem.Allocator,
    widget_command: WidgetCommand,
    textedits: std.ArrayList(WidgetTextEdit),
    sdl_window: *c.SDL_Window,
    sdl_renderer: *c.SDL_Renderer,

    /// widget_text_edit_pos is the position of the main WidgetTextEdit in the
    /// window. Independant of the scale (i.e. position of the widget in window_scaled_size).
    widget_text_edit_pos: Vec2u,

    /// window_pixel_size is the amount of pixel used to draw the window.
    /// E.g. in a normal resolution, a window of size 800x800 has window_pixel_size
    /// equals to 800x800, whereas on a retina/hidpi screen (let's say with a scale of 1.5x)
    /// the window_pixel_size will be equal to 1600x1600.
    window_pixel_size: Vec2u,
    /// window_scaled_size is the window size.
    /// E.g. in normal resolution, a window of size 800x800 has window_scaled_size
    /// of value 800x800. In a retina/hidpi screen, the window_scaled_size is also
    /// equals to 800x800.
    window_scaled_size: Vec2u,
    /// window_scaling contains the scale between the actual GL rendered
    /// surface and the window size.
    window_scaling: f32,

    // TODO(remy): comment
    // TODO(remy): tests
    font_lowdpi: Font,
    font_lowdpibigfont: Font,
    font_hidpi: Font,
    font_custom: ?Font,
    current_font: Font,
    font_mode: FontMode,

    /// mainloop is running flag.
    is_running: bool,

    /// current_widget_text_edit_tab is the currently selected widget text in the
    /// opened WidgetTextEdits/editors/buffers.
    current_widget_text_edit_tab: usize,

    /// focused_widget is the widget which currently has the focus and receives
    /// the events from the keyboard and mouse.
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

        // load the fonts

        var font_lowdpi = try Font.init(allocator, sdl_renderer.?, "./res/UbuntuMono-Regular.ttf", 18);
        var font_lowdpibigfont = try Font.init(allocator, sdl_renderer.?, "./res/UbuntuMono-Regular.ttf", 22);
        var font_hidpi = try Font.init(allocator, sdl_renderer.?, "./res/UbuntuMono-Regular.ttf", 32);

        // return the created app
        return App{
            .allocator = allocator,
            .widget_text_edit_pos = Vec2u{ .a = 0, .b = 8 * 4 },
            .textedits = std.ArrayList(WidgetTextEdit).init(allocator),
            .widget_command = try WidgetCommand.init(allocator),
            .current_widget_text_edit_tab = 0,
            .sdl_renderer = sdl_renderer.?,
            .is_running = true,
            .sdl_window = sdl_window.?,
            .font_custom = undefined,
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
        while (i < self.textedits.items.len) : (i += 1) {
            self.textedits.items[i].deinit();
        }
        self.textedits.deinit();

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
        var editor = WidgetTextEdit.initWithBuffer(self.allocator, buffer);
        try self.textedits.append(editor);
    }

    // FIXME(remy): this method isn't testing anything and will crash the
    // app if no file is opened.
    pub fn currentWidgetTextEdit(self: App) *WidgetTextEdit {
        return &self.textedits.items[self.current_widget_text_edit_tab];
    }

    pub fn increaseFont(self: *App) void {
        var font = Font.init(self.allocator, self.sdl_renderer, "./res/UbuntuMono-Regular.ttf", self.current_font.font_size + 2) catch |err| {
            std.log.err("App.increaseFont: can't load temporary font: {}", .{err});
            return;
        };

        // FIXME(remy): we have to de-allocate the previous one
        // if (self.font_custom) |custom| {
        // custom.deinit();
        // }

        self.font_custom = font;
        self.current_font = font;
    }

    fn render(self: *App) void {
        // grab screen information every render pass
        // -----------------------------------------

        self.refreshWindowPixelSize();
        self.refreshWindowScaledSize();
        self.refreshDPIMode();
        var scaler = Scaler{ .scale = self.window_scaling };
        var one_char_size = self.oneCharSize();

        // render list
        // -----------

        // clean up between passes

        _ = c.SDL_SetRenderDrawColor(self.sdl_renderer, 30, 30, 30, 255);
        _ = c.SDL_RenderClear(self.sdl_renderer);

        // editor window

        var widget_text_edit = &self.textedits.items[0];
        widget_text_edit.render(
            self.sdl_renderer,
            self.current_font,
            scaler,
            self.widget_text_edit_pos,
            Vec2u{ .a = self.window_scaled_size.a, .b = self.window_scaled_size.b - one_char_size.b },
            one_char_size,
        );

        if (self.focused_widget == .Command) {
            self.widget_command.render(
                self.sdl_renderer,
                self.current_font,
                scaler,
                self.window_scaled_size, // used for the overlay
                Vec2u{ .a = @floatToInt(usize, @intToFloat(f32, self.window_scaled_size.a) * 0.1), .b = 50 },
                Vec2u{ .a = @floatToInt(usize, @intToFloat(f32, self.window_scaled_size.a) * 0.8), .b = 50 },
                one_char_size,
            );
        }

        // rendering
        _ = c.SDL_RenderPresent(self.sdl_renderer);
    }

    fn setFontMode(self: *App, font_mode: FontMode) void {
        switch (font_mode) {
            .LowDPI => {
                self.current_font = self.font_lowdpi;
                self.widget_text_edit_pos.b = 16 + 4;
            },
            .LowDPIBigFont => {
                self.current_font = self.font_lowdpibigfont;
                self.widget_text_edit_pos.b = 20 + 4;
            },
            .HiDPI => {
                self.current_font = self.font_hidpi;
                self.widget_text_edit_pos.b = 16 + 4;
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
        // the viewport may have to be resized
        self.onWindowResized();
    }

    /// oneCharSize returns the bounding box of one text char.
    fn oneCharSize(self: App) Vec2u {
        return Vec2u{
            .a = @floatToInt(usize, @intToFloat(f32, self.current_font.font_size / 2) / self.window_scaling),
            .b = @floatToInt(usize, @intToFloat(f32, self.current_font.font_size) / self.window_scaling),
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
    }

    /// mainloop of the application.
    pub fn mainloop(self: *App) !void {
        var event: c.SDL_Event = undefined;
        self.is_running = true;
        var to_render = true;
        c.SDL_StartTextInput(); // TODO(remy): confirm it's the good way of using this

        const frame_per_second = 60;
        const max_ms_skip = 1000 / frame_per_second;
        var start = std.time.milliTimestamp();
        var focused_widget = self.focused_widget;

        // immediately trigger a first render pass for responsiveness when the
        // window appears.
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
            std.time.sleep(itou(max_sleep_ms * std.time.ns_per_ms));
        }

        c.SDL_StopTextInput();
    }

    fn commandEvents(self: *App, event: c.SDL_Event) void {
        switch (event.type) {
            c.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    c.SDLK_RETURN => {
                        self.widget_command.interpret(self) catch |err| {
                            std.log.err("App.commandEvents: can't start interpert: {}", .{err});
                            return;
                        };
                        self.focused_widget = FocusedWidget.Editor;
                        self.widget_command.reset();
                    },
                    c.SDLK_ESCAPE => {
                        self.focused_widget = FocusedWidget.Editor;
                        self.widget_command.reset();
                    },
                    c.SDLK_BACKSPACE => {
                        self.widget_command.onBackspace();
                    },
                    else => {},
                }
            },
            c.SDL_TEXTINPUT => {
                _ = self.widget_command.onTextInput(readTextFromSDLInput(&event.text.text));
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
                        self.currentWidgetTextEdit().onReturn();
                    },
                    c.SDLK_ESCAPE => _ = self.currentWidgetTextEdit().onEscape(),
                    c.SDLK_COLON => {
                        if (self.currentWidgetTextEdit().input_mode == .Command) {
                            self.focused_widget = FocusedWidget.Command;
                        }
                    },
                    c.SDLK_BACKSPACE => {
                        self.currentWidgetTextEdit().onBackspace();
                    },
                    c.SDLK_EQUALS => {
                        if ((ctrl or cmd) and shift) {
                            self.increaseFont();
                        }
                    },
                    c.SDLK_TAB => {
                        self.currentWidgetTextEdit().onTab(shift); // TODO(remy): support shift-tab
                    },
                    else => {
                        if (ctrl) {
                            _ = self.currentWidgetTextEdit().onCtrlKeyDown(event.key.keysym.sym, ctrl, cmd);
                        }
                    },
                }
            },
            c.SDL_TEXTINPUT => {
                _ = self.currentWidgetTextEdit().onTextInput(readTextFromSDLInput(&event.text.text));
            },
            c.SDL_MOUSEWHEEL => {
                _ = self.currentWidgetTextEdit().onMouseWheel(Vec2i{ .a = event.wheel.x, .b = event.wheel.y });
            },
            c.SDL_MOUSEMOTION => {
                self.currentWidgetTextEdit().onMouseMove(sdlMousePosToVec2u(event.motion.x, event.motion.y), self.widget_text_edit_pos);
            },
            c.SDL_MOUSEBUTTONDOWN => {
                self.currentWidgetTextEdit().onMouseStartSelection(sdlMousePosToVec2u(event.button.x, event.button.y), self.widget_text_edit_pos);
            },
            c.SDL_MOUSEBUTTONUP => {
                self.currentWidgetTextEdit().onMouseStopSelection(sdlMousePosToVec2u(event.button.x, event.button.y), self.widget_text_edit_pos);
            },
            else => {},
        }
    }

    /// sdlMousePosToVec2u converts the mouse position in c_ints into a Vec2u
    /// If the click happened outside of the left/top window, the concerned value
    /// will be 0.
    fn sdlMousePosToVec2u(x: c_int, y: c_int) Vec2u {
        var rv = Vec2u{ .a = 0, .b = 0 };
        if (x < 0) {
            rv.a = 0;
        } else {
            rv.a = @intCast(usize, x);
        }
        if (y < 0) {
            rv.b = 0;
        } else {
            rv.b = @intCast(usize, y);
        }
        return rv;
    }

    /// readTextFromSDLInput reads and sizes the received text from the SDL_TEXTINPUT event.
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

test "app sdlMousePosToVec2u" {
    var rv = App.sdlMousePosToVec2u(5, 15);
    try expect(rv.a == 5);
    try expect(rv.b == 15);
    rv = App.sdlMousePosToVec2u(-10, 15);
    try expect(rv.a == 0);
    try expect(rv.b == 15);
    rv = App.sdlMousePosToVec2u(5, -15);
    try expect(rv.a == 5);
    try expect(rv.b == 0);
    rv = App.sdlMousePosToVec2u(-10, -15);
    try expect(rv.a == 0);
    try expect(rv.b == 0);
}
