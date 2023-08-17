const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const Colors = @import("colors.zig");
const Draw = @import("draw.zig").Draw;
const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;

pub const WidgetMessageBoxType = enum {
    LSPDiagnostic,
    Error,
};

pub const WidgetMessageBoxOverlay = enum {
    WithOverlay,
    WithoutOverlay,
};

pub const WidgetMessageBox = struct {
    allocator: std.mem.Allocator,
    label: U8Slice,
    message: WidgetMessageBoxType,
    overlay: WidgetMessageBoxOverlay,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) WidgetMessageBox {
        return WidgetMessageBox{
            .allocator = allocator,
            .label = U8Slice.initEmpty(allocator),
            .message = undefined,
            .overlay = .WithOverlay,
        };
    }

    pub fn deinit(self: *WidgetMessageBox) void {
        self.label.deinit();
    }

    // Methods
    // -------

    pub fn set(self: *WidgetMessageBox, label: []const u8, message: WidgetMessageBoxType, overlay: WidgetMessageBoxOverlay) !void {
        self.label.deinit();
        self.label = try U8Slice.initFromSlice(self.allocator, label);
        self.message = message;
        self.overlay = overlay;
    }

    pub fn render(
        self: WidgetMessageBox,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        window_scaled_size: Vec2u,
        _: Vec2u, // one_char_size
    ) void {
        // overlay
        if (self.overlay == .WithOverlay) {
            Draw.fillRect(sdl_renderer, scaler, Vec2u{ .a = 0, .b = 0 }, window_scaled_size, Vec4u{ .a = 20, .b = 20, .c = 20, .d = 130 });
        }

        switch (self.message) {
            .LSPDiagnostic => {
                const position = Vec2u{ .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.05)), .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.b)) * 0.7)) };
                const size = Vec2u{ .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.9)), .b = 50 };

                // dark background
                Draw.fillRect(sdl_renderer, scaler, position, size, Vec4u{ .a = 20, .b = 20, .c = 20, .d = 240 });

                // content
                Draw.text(font, scaler, Vec2u{ .a = position.a + 15, .b = position.b + 15 }, size.a - 30, Colors.red, self.label.bytes());
            },
            else => {
                const position = Vec2u{ .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.1)), .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.b)) * 0.1)) };
                const size = Vec2u{ .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.8)), .b = 50 };

                // dark background
                Draw.fillRect(sdl_renderer, scaler, position, size, Vec4u{ .a = 20, .b = 20, .c = 20, .d = 240 });

                // content
                Draw.text(font, scaler, Vec2u{ .a = position.a + 15, .b = position.b + 15 }, size.a - 30, Colors.white, self.label.bytes());
            },
        }
    }
};
