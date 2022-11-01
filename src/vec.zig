const c = @import("clib.zig").c;

// TODO(remy): comment
// TODO(remy): struct name isn't ideal
pub const Vec2i = struct { a: i64, b: i64 };
pub const Vec2f = struct { a: f32, b: f32 };
pub const Vec2u = struct { a: usize, b: usize };

/// Vec2itou turns a Vec2i in Vec2u.
/// Uses with care since the conversion may corrupt the data.
pub fn Vec2itou(in: Vec2i) Vec2u {
    return Vec2u{ .a = @intCast(usize, in.a), .b = @intCast(usize, in.b) };
}

/// Vec2itou turns a Vec2i in Vec2u.
/// Uses with care since the conversion may corrupt the data.
pub fn Vec2utoi(in: Vec2u) Vec2i {
    return Vec2i{ .a = @intCast(i64, in.a), .b = @intCast(i64, in.b) };
}
pub fn ImVec2(x: f32, y: f32) c.ImVec2 {
    return c.ImVec2{ .x = x, .y = y };
}
