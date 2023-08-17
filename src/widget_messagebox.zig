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
    LSPHover,
    Error,
};

pub const WidgetMessageBoxOverlay = enum {
    WithOverlay,
    WithoutOverlay,
};

pub const WidgetMessageBox = struct {
    allocator: std.mem.Allocator,
    labels: std.ArrayList(U8Slice),
    message: WidgetMessageBoxType,
    overlay: WidgetMessageBoxOverlay,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) WidgetMessageBox {
        return WidgetMessageBox{
            .allocator = allocator,
            .labels = std.ArrayList(U8Slice).init(allocator),
            .message = undefined,
            .overlay = .WithOverlay,
        };
    }

    pub fn deinit(self: *WidgetMessageBox) void {
        self.resetLabels();
    }

    fn resetLabels(self: *WidgetMessageBox) void {
        for (self.labels.items) |item| {
            item.deinit();
        }
        self.labels.deinit();
    }

    // Methods
    // -------

    pub fn set(self: *WidgetMessageBox, label: []const u8, message: WidgetMessageBoxType, overlay: WidgetMessageBoxOverlay) !void {
        self.resetLabels();
        self.labels = std.ArrayList(U8Slice).init(self.allocator);
        const slice = try U8Slice.initFromSlice(self.allocator, label);
        try self.labels.append(slice);
        self.message = message;
        self.overlay = overlay;
    }

    pub fn setMultiple(self: *WidgetMessageBox, labels: std.ArrayList(U8Slice), message: WidgetMessageBoxType, overlay: WidgetMessageBoxOverlay) !void {
        self.resetLabels();
        self.labels = std.ArrayList(U8Slice).init(self.allocator);
        for (labels.items) |label| {
            const copy = try label.copy(self.allocator);
            try self.labels.append(copy);
        }
        self.message = message;
        self.overlay = overlay;
    }

    pub fn render(
        self: WidgetMessageBox,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        window_scaled_size: Vec2u,
        one_char_size: Vec2u, // one_char_size
    ) void {

        // overlay
        if (self.overlay == .WithOverlay) {
            Draw.fillRect(sdl_renderer, scaler, Vec2u{ .a = 0, .b = 0 }, window_scaled_size, Vec4u{ .a = 20, .b = 20, .c = 20, .d = 130 });
        }

        const lines_to_draw = @min(10, self.labels.items.len);

        switch (self.message) {
            .LSPDiagnostic, .LSPHover => {
                var color = Colors.light_gray;
                if (self.message == .LSPDiagnostic) {
                    color = Colors.red;
                }

                const lines_pixel_height: usize = lines_to_draw * (one_char_size.b + 1);
                const position = Vec2u{
                    .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.05)),
                    .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.b)) * 0.7)) - lines_pixel_height,
                };
                const size = Vec2u{
                    .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.9)),
                    .b = 30 + lines_pixel_height,
                };

                // dark background
                Draw.fillRect(sdl_renderer, scaler, position, size, Vec4u{ .a = 20, .b = 20, .c = 20, .d = 240 });

                // content

                var y = position.b + 15;
                var i: usize = 0;
                for (self.labels.items) |label| {
                    Draw.text(font, scaler, Vec2u{ .a = position.a + 15, .b = y }, size.a - 30, color, label.bytes());
                    y += one_char_size.b + 1;
                    i += 1;
                    if (i > 10) {
                        break;
                    }
                }
            },
            else => {
                const position = Vec2u{
                    .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.1)),
                    .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.b)) * 0.1)),
                };
                const size = Vec2u{
                    .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.8)),
                    .b = 50,
                };

                // dark background
                Draw.fillRect(sdl_renderer, scaler, position, size, Vec4u{ .a = 20, .b = 20, .c = 20, .d = 240 });

                // content
                Draw.text(font, scaler, Vec2u{ .a = position.a + 15, .b = position.b + 15 }, size.a - 30, Colors.white, self.labels.items[0].bytes());
            },
        }
    }
};
