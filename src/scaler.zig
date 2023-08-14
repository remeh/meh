const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;

/// Scaler is used to pass both the current window scaling and the methods
/// to turn a vector from virtual window scaled size to window real pixel size.
pub const Scaler = struct {
    scale: f32,

    pub fn Scaleu(self: Scaler, in: usize) usize {
        return @as(usize, @intFromFloat(@as(f32, @floatFromInt(in)) * self.scale));
    }

    pub fn Scale2u(self: Scaler, in: Vec2u) Vec2u {
        return Vec2u{
            .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(in.a)) * self.scale)),
            .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(in.b)) * self.scale)),
        };
    }

    pub fn Scale2i(self: Scaler, in: Vec2i) Vec2i {
        return Vec2i{
            .a = @as(i64, @intFromFloat(@as(f32, @floatFromInt(in.a)) * self.scale)),
            .b = @as(i64, @intFromFloat(@as(f32, @floatFromInt(in.b)) * self.scale)),
        };
    }
};
