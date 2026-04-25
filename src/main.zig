const std = @import("std");
const builtin = @import("builtin");
const c = @import("clib.zig").c;

const App = @import("app.zig").App;
const Fd = @import("fd.zig").Fd;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    // app
    var app = try App.init(allocator, io);
    defer app.deinit();

    // nothing passed as argument
    if (args.len <= 1) {
        const results = Fd.search(app.allocator, ".", app.working_dir.bytes()) catch |err| {
            std.log.err("main: can't exec 'fd {s}': {}", .{ ".", err });
            return;
        };
        app.openFdResults(results);
    } else {
        // stat the first parameter, if it is a directory, we want
        // to use it as the working dir and open the file opener
        // in this directory.
        const first_arg = args[1];
        const stat = std.Io.Dir.cwd().statFile(io, first_arg, .{}) catch |err| {
            std.log.debug("Error while opening the file: {}. Closing.", .{err});
            return;
        };
        if (stat.kind == .directory) {
            const fullpath = try std.Io.Dir.cwd().realPathFileAlloc(io, first_arg, allocator);
            defer allocator.free(fullpath);
            app.working_dir.reset();
            try app.working_dir.appendConst(fullpath);
            app.openFileOpener();
        } else {
            // otherwise, opens all of them as files
            var i: usize = 1;
            while (i < args.len) : (i += 1) {
                app.openFile(args[i]) catch {
                    if (args.len == 2) {
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
