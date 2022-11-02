const std = @import("std");
const builtin = @import("builtin");
const c = @import("clib.zig").c;

const App = @import("app.zig").App;

pub fn main() !void {
    // TODO(remy): should we use a different allocator?
    var app = try App.init(std.heap.page_allocator);
    if (std.mem.len(std.os.argv) <= 1) {
        try app.openFile("src/app.zig");
    } else {
        var arg = std.os.argv[1];
        var len = std.mem.len(arg);
        try app.openFile(arg[0..len]);
    }
    errdefer app.deinit();
    try app.mainloop();

    app.deinit();
}
