const std = @import("std");
const U8Slice = @import("u8slice.zig").U8Slice;

pub const ExecResult = struct {
    allocator: std.mem.Allocator,
    stdout: []u8,
    stderr: []u8,

    pub fn deinit(self: ExecResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};

// TODO(remy): comment
// TODO(remy): unit test
pub const Exec = struct {
    pub fn run(allocator: std.mem.Allocator, command: []const u8, cwd: []const u8) !ExecResult {
        var args = std.ArrayList([]const u8).init(allocator);
        defer args.deinit();

        var it = std.mem.splitScalar(u8, command, ' ');
        while (it.next()) |arg| {
            try args.append(arg);
        }

        // FIXME(remy): this has a bug in the stdlib, if within the `exec` call
        // the spawn call succeed, but collecting the output doesn't, it doesn't
        // properly tear down the process. Using a 25MB read buffer for now to
        // avoid this as much as possible but in the future, I would like to return
        // a `RipgrepError.TooManyResults` instead in order to display something nice.
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = args.items,
            .cwd = cwd,
            .max_output_bytes = 25 * 1024 * 1024,
        });
        errdefer {
            allocator.free(result.stderr);
            allocator.free(result.stdout);
        }

        return ExecResult{
            .stdout = result.stdout,
            .stderr = result.stderr,
            .allocator = allocator,
        };
    }
};
