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
        // directly open the file opener
        app.openFileOpener();
    } else {
        // stat the first parameter, if it is a directory, we want
        // to use it as the working dir and open the file opener
        // in this directory.
        const first_arg = std.os.argv[1];
        const first_arg_as_const = first_arg[0..std.mem.len(first_arg)];
        const stat = try std.fs.cwd().statFile(first_arg_as_const);
        if (stat.kind == .directory) {
            const fullpath = try std.fs.realpathAlloc(allocator, first_arg_as_const);
            defer allocator.free(fullpath);
            app.working_dir.reset();
            try app.working_dir.appendConst(fullpath);
            app.openFileOpener();
        } else {
            // otherwise, opens all of them as files
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
    }

    try app.mainloop();
}
