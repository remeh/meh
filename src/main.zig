const std = @import("std");
const builtin = @import("builtin");
const c = @import("clib.zig").c;

const App = @import("app.zig").App;

pub fn main() !void {
    var app = try App.init(std.heap.page_allocator);
    try app.openFile("src/app.zig");
    errdefer app.deinit();
    try app.mainloop();
}
