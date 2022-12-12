const std = @import("std");

const U8Slice = @import("u8slice.zig").U8Slice;

pub const RipgrepResults = struct {
    alocator: std.mem.Allocator,
    results: std.ArrayList(U8Slice),

    pub fn deinit(self: *RipgrepResults) void {
        self.results.deinit();
        self.allocator.free(self.results);
    }
};

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
