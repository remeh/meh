const c = @import("clib.zig").c;

pub const Vec2i = struct { a: i64, b: i64 };
pub const Vec2f = struct { a: f32, b: f32 };
pub const Vec2u = struct { a: usize, b: usize };
pub const Vec4u = struct { a: usize, b: usize, c: usize, d: usize };

/// Vec2itou turns a Vec2i into a Vec2u.
/// Uses with care since the conversion may corrupt the data.
pub fn Vec2itou(in: Vec2i) Vec2u {
    return Vec2u{ .a = @as(usize, @intCast(in.a)), .b = @as(usize, @intCast(in.b)) };
}

/// Vec2itou turns a Vec2i into a Vec2u.
/// Uses with care since the conversion may corrupt the data.
pub fn Vec2utoi(in: Vec2u) Vec2i {
    return Vec2i{ .a = @as(i64, @intCast(in.a)), .b = @as(i64, @intCast(in.b)) };
}

/// Vec2ftou turns a Vec2f into a Vec2u.
/// Uses with care since the conversion may corrupt the data.
pub fn Vec2ftou(in: Vec2f) Vec2u {
    return Vec2u{ .a = @as(usize, @intFromFloat(in.a)), .b = @as(usize, @intFromFloat(in.b)) };
}

pub fn itou(in: i64) usize {
    return @as(usize, @intCast(in));
}

pub fn utoi(in: usize) i64 {
    return @as(i64, @intCast(in));
}
