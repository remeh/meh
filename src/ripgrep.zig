const std = @import("std");

pub const Ripgrep = struct {
    pub fn search(allocator: std.mem.Allocator, pattern: []const u8, cwd: []const u8) !void {
        var args = std.ArrayList([]const u8).init(allocator);
        defer args.deinit();

        try args.append("rg");
        try args.append("--vimgrep");
        try args.append(pattern);

        var result = try std.ChildProcess.exec(.{
            .allocator = allocator,
            .argv = args.items,
            .cwd = cwd,
        });

        std.log.debug("{s}", .{result.stdout});

        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
    }
};
