const Vec4u = @import("vec.zig").Vec4u;

pub const white = Vec4u{
    .a = 255,
    .b = 255,
    .c = 255,
    .d = 255,
};

pub const light_gray = Vec4u{
    .a = 190,
    .b = 190,
    .c = 190,
    .d = 255,
};

pub const gray = Vec4u{
    .a = 120,
    .b = 120,
    .c = 120,
    .d = 255,
};

pub const dark_gray = Vec4u{
    .a = 20,
    .b = 20,
    .c = 20,
    .d = 255,
};
