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
    ExecOutput,
    LSPDiagnostic,
    LSPHover,
    LSPMessage,
    Error,
};

pub const WidgetMessageBoxOverlay = enum {
    WithOverlay,
    WithoutOverlay,
};

pub const WidgetMessageBox = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayListUnmanaged(U8Slice),
    message: WidgetMessageBoxType,
    overlay: WidgetMessageBoxOverlay,
    x_offset: usize,
    y_offset: usize,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) WidgetMessageBox {
        return WidgetMessageBox{
            .allocator = allocator,
            .lines = std.ArrayListUnmanaged(U8Slice).empty,
            .message = undefined,
            .overlay = .WithOverlay,
            .x_offset = 0,
            .y_offset = 0,
        };
    }

    pub fn deinit(self: *WidgetMessageBox) void {
        self.resetLines();
    }

    // Methods
    // -------

    /// resetLines frees memory of all managed lines and empties the lines list.
    pub fn resetLines(self: *WidgetMessageBox) void {
        for (self.lines.items) |*item| {
            item.deinit();
        }
        self.lines.shrinkAndFree(self.allocator, 0);
    }

    /// set prepares the messagebox to display a single line.
    pub fn set(self: *WidgetMessageBox, line: []const u8, message: WidgetMessageBoxType, overlay: WidgetMessageBoxOverlay) !void {
        self.resetLines();
        const slice = try U8Slice.initFromSlice(self.allocator, line);
        try self.lines.append(self.allocator, slice);
        self.message = message;
        self.overlay = overlay;
        self.x_offset = 0;
        self.y_offset = 0;
    }

    /// append inserts a new line at the end.
    pub fn append(self: *WidgetMessageBox, line: []const u8) !void {
        const slice = try U8Slice.initFromSlice(self.allocator, line);
        try self.lines.append(self.allocator, slice);
    }

    /// setMultiple prepares the messagebox to display multiple lines.
    pub fn setMultiple(self: *WidgetMessageBox, lines: std.ArrayListUnmanaged(U8Slice), message: WidgetMessageBoxType, overlay: WidgetMessageBoxOverlay) !void {
        self.resetLines();
        for (lines.items) |line| {
            const copy = try line.copy(self.allocator);
            try self.lines.append(self.allocator, copy);
        }
        self.message = message;
        self.overlay = overlay;
        self.x_offset = 0;
        self.y_offset = 0;
    }

    /// render renders the messagebox on the given renderer.
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

        const lines_to_draw = @min(10, self.lines.items.len);

        switch (self.message) {
            .ExecOutput, .LSPDiagnostic, .LSPHover, .LSPMessage => {
                var color = Colors.light_gray;
                if (self.message == .LSPDiagnostic) {
                    color = Colors.red;
                }

                const lines_pixel_height: usize = lines_to_draw * (one_char_size.b + 1);
                const position = Vec2u{
                    .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.05)),
                    .b = window_scaled_size.b - lines_pixel_height - 50,
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
                for (self.lines.items) |line| {
                    if (self.y_offset > i) {
                        i += 1;
                        continue;
                    }
                    var text: []const u8 = ""; // TODO(remy): doesn't support utf8
                    if (self.x_offset < line.size()) {
                        text = line.bytes()[self.x_offset..];
                    }
                    Draw.text(font, scaler, Vec2u{ .a = position.a + 15, .b = y }, size.a - 30, color, text);
                    y += one_char_size.b + 1;
                    i += 1;
                    if (i > self.y_offset + 10) {
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

                const line = self.lines.items[0];
                var text: []const u8 = ""; // TODO(remy): doesn't support utf8
                if (self.x_offset < line.size()) {
                    text = line.bytes()[self.x_offset..];
                }

                // content
                Draw.text(font, scaler, Vec2u{ .a = position.a + 15, .b = position.b + 15 }, size.a - 30, Colors.white, text);
            },
        }
    }
};

test "widget_message_box main tests" {
    const allocator = std.testing.allocator;
    var msgbox = WidgetMessageBox.init(allocator);
    defer msgbox.deinit();

    try msgbox.append("hello");
    try msgbox.append("world");
    try std.testing.expectEqual(2, msgbox.lines.items.len);
    try std.testing.expectEqualStrings("hello", msgbox.lines.items[0].bytes());
    try std.testing.expectEqualStrings("world", msgbox.lines.items[1].bytes());

    msgbox.resetLines();
    try msgbox.append("hello world");
    try std.testing.expectEqual(1, msgbox.lines.items.len);
    try std.testing.expectEqualStrings("hello world", msgbox.lines.items[0].bytes());

    try msgbox.append("second line");
    try std.testing.expectEqual(2, msgbox.lines.items.len);

    try msgbox.set("an lsp diagnostic", .LSPDiagnostic, .WithOverlay);
    try std.testing.expectEqual(1, msgbox.lines.items.len);
    try std.testing.expectEqualStrings("an lsp diagnostic", msgbox.lines.items[0].bytes());

    var lines = std.ArrayListUnmanaged(U8Slice).empty;
    try lines.append(allocator, try U8Slice.initFromSlice(allocator, "hello"));
    try lines.append(allocator, try U8Slice.initFromSlice(allocator, "world"));
    try msgbox.setMultiple(lines, .LSPDiagnostic, .WithOverlay);
    try std.testing.expectEqual(2, msgbox.lines.items.len);
    try std.testing.expectEqualStrings("hello", msgbox.lines.items[0].bytes());
    try std.testing.expectEqualStrings("world", msgbox.lines.items[1].bytes());

    for (lines.items) |line| {
        line.deinit();
    }
    lines.deinit(allocator);
}
