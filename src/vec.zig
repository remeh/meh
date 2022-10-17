const c = @import("clib.zig").c;

// TODO(remy): comment me
// TODO(remy): struct name isn't ideal
// TODO(remy): (a,b) isn't optimal
pub const Vec2i = struct { a: i64, b: i64 };

pub fn ImVec2(x: f32, y: f32) c.ImVec2 {
    return c.ImVec2_ImVec2_Float(x, y).*;
}
