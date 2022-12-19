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
    if (std.os.argv.len <= 1) {
        try app.openFile("src/app.zig");
    } else {
        var i: usize = 1;
        while (i < std.os.argv.len) : (i += 1) {
            var arg = std.os.argv[i];
            var len = std.mem.len(arg);
            try app.openFile(arg[0..len]);
        }
    }
    errdefer app.deinit();
    try app.mainloop();

    app.deinit();

    //    _ = gpa.detectLeaks();
}
