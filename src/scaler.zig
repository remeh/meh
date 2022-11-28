const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;

/// Scaler is used to pass both the current window scaling and the methods
/// to turn a vector from virtual window scaled size to window real pixel size.
pub const Scaler = struct {
    scale: f32,

    pub fn Scaleu(self: Scaler, in: usize) usize {
        return @floatToInt(usize, @intToFloat(f32, in) * self.scale);
    }

    pub fn Scale2u(self: Scaler, in: Vec2u) Vec2u {
        return Vec2u{
            .a = @floatToInt(usize, @intToFloat(f32, in.a) * self.scale),
            .b = @floatToInt(usize, @intToFloat(f32, in.b) * self.scale),
        };
    }

    pub fn Scale2i(self: Scaler, in: Vec2i) Vec2i {
        return Vec2i{
            .a = @floatToInt(i64, @intToFloat(f32, in.a) * self.scale),
            .b = @floatToInt(i64, @intToFloat(f32, in.b) * self.scale),
        };
    }
};
