const std = @import("std");
const builtin = @import("builtin");
const c = @import("clib.zig").c;

const App = @import("app.zig").App;

pub fn main() !void {
    // TODO(remy): configure the allocator properly
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = 8,
    }){};
    const allocator = gpa.allocator();
    defer _ = gpa.detectLeaks();

    // app

    var app = try App.init(allocator);
    defer app.deinit();

    // open the files passed as argument
    if (std.os.argv.len <= 1) {
        // TODO(remy): open a scratch buffer
        try app.openFile("src/app.zig");
    } else {
        var i: usize = 1;
        while (i < std.os.argv.len) : (i += 1) {
            var arg = std.os.argv[i];
            const len = std.mem.len(arg);
            app.openFile(arg[0..len]) catch {
                if (std.os.argv.len == 2) {
                    // do not open the app if there is only one file to open
                    // and we can't open it
                    return;
                }
            };
        }
    }

    try app.mainloop();
}
