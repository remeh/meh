const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;

// TODO(remy): color
pub const WidgetLabel = struct {
    allocator: std.mem.Allocator,
    text: U8Slice,
    position: Vec2u,

    pub fn initFromU8Slice(allocator: std.mem.Allocator, position: Vec2u, text: U8Slice) WidgetLabel {
        return WidgetLabel{
            .allocator = allocator,
            .content = text,
            .position = position,
        };
    }

    pub fn initFromSlice(allocator: std.mem.Allocator, position: Vec2u, text: []const u8) !WidgetLabel {
        return WidgetLabel{
            .allocator = allocator,
            .text = try U8Slice.initFromSlice(allocator, text),
            .position = position,
        };
    }

    pub fn deinit(self: *WidgetLabel) void {
        self.text.deinit();
    }

    // Methods
    // -------

    pub fn render(self: WidgetLabel, scaler: Scaler, font: Font) void {
        var pos = scaler.Scale2u(self.position);
        font.drawText(pos, self.text.bytes());
    }
};
