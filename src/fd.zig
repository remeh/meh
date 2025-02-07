const std = @import("std");
const TokenIterator = std.mem.TokenIterator;

const U8Slice = @import("u8slice.zig").U8Slice;
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;

pub const FdError = error{
    TooManyResults,
};

pub const FdResults = struct {
    allocator: std.mem.Allocator,
    stdout: []u8,

    pub fn iterator(self: FdResults, allocator: std.mem.Allocator) FdResultsIterator {
        return FdResultsIterator{
            .allocator = allocator,
            .it = std.mem.tokenize(u8, self.stdout, "\n"),
        };
    }

    pub fn deinit(self: FdResults) void {
        if (self.stdout.len > 0) {
            self.allocator.free(self.stdout);
        }
    }
};

pub const FdResult = struct {
    filepath: U8Slice,
};

pub const FdResultsIterator = struct {
    allocator: std.mem.Allocator,
    it: TokenIterator(u8, .any),

    pub fn next(self: *FdResultsIterator) ?FdResult {
        if (self.it.next()) |line| {
            const filepath = U8Slice.initFromSlice(self.allocator, line) catch |err| {
                std.log.err("FdResultsIterator: can't allocate: {}", .{err});
                return null;
            };

            return FdResult{
                .filepath = filepath,
            };
        }
        return null;
    }
};

pub const Fd = struct {
    pub fn search(allocator: std.mem.Allocator, parameters: []const u8, cwd: []const u8) !FdResults {
        var args = std.ArrayList([]const u8).init(allocator);
        defer args.deinit();

        try args.append("fd");
        try args.append("--type");
        try args.append("file");
        try args.append(parameters);

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

        // do not free the stdout, it will be owned by the RipgrepResults
        defer allocator.free(result.stderr);

        return FdResults{
            .allocator = allocator,
            .stdout = result.stdout,
        };
    }
};
