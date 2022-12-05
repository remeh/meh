const std = @import("std");
const builtin = @import("builtin");
const c = @import("clib.zig").c;

const App = @import("app.zig").App;

pub fn main() !void {
    // TODO(remy): configure the allocator properly
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    // app

    var app = try App.init(allocator);
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

    //    _ = gpa.detectLeaks();
}
