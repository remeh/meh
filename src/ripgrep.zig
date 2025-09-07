const std = @import("std");
const TokenIterator = std.mem.TokenIterator;

const U8Slice = @import("u8slice.zig").U8Slice;
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;

pub const RipgrepError = error{
    NoSearchPattern,
    TooManyResults,
};

pub const RipgrepResults = struct {
    allocator: std.mem.Allocator,
    stdout: []u8,

    pub fn iterator(self: RipgrepResults, allocator: std.mem.Allocator) RipgrepResultsIterator {
        return RipgrepResultsIterator{
            .allocator = allocator,
            .it = std.mem.tokenizeScalar(u8, self.stdout, '\n'),
        };
    }

    pub fn deinit(self: RipgrepResults) void {
        if (self.stdout.len > 0) {
            self.allocator.free(self.stdout);
        }
    }
};

/// RipgrepResult are only used to transmit a result to a caller:
/// the filename and content must be deallocated by the caller
/// using the same allocator than the one used to create the iterator
/// having created the RipgrepResult.
pub const RipgrepResult = struct {
    filename: U8Slice,
    content: U8Slice,
    line_number: usize,
    column: usize,
};

pub const RipgrepResultsIterator = struct {
    allocator: std.mem.Allocator,
    it: TokenIterator(u8, .scalar),

    pub fn next(self: *RipgrepResultsIterator) ?RipgrepResult {
        if (self.it.next()) |line| {
            // using an utf8iterator to support filename with utf8 glyphs,
            // that's potentially overkill and std.mem.split may have done the same
            // job, but on top of that, the code would not be really different since
            // std.mem.split also returns an iterator.
            var it = UTF8Iterator.init(line, 0) catch |err| {
                std.log.err("RipgrepResultsIterator.next: can't create an utf8 iterator: {}", .{err});
                return null;
            };

            var start_idx: usize = 0;
            var idx: usize = 0;
            var token: usize = 0;
            var filename = U8Slice.initEmpty(self.allocator);
            var content = U8Slice.initEmpty(self.allocator);
            var line_number: usize = 0;
            var column: usize = 0;

            while (true) {
                if (it.glyph()[0] == ':') {
                    switch (token) {
                        // filename
                        // --------
                        0 => {
                            filename.appendConst(line[start_idx..idx]) catch |err| {
                                filename.deinit();
                                content.deinit();
                                std.log.err("RipgrepResultsIterator: can't appendConst the filename: {}", .{err});
                                return null;
                            };
                            start_idx = idx + 1;
                        },
                        // line number
                        // -----------
                        1 => {
                            line_number = std.fmt.parseInt(usize, line[start_idx..idx], 10) catch |err| {
                                filename.deinit();
                                content.deinit();
                                std.log.err("RipgrepResultsIterator: can't read line number: {}", .{err});
                                return null;
                            };
                            start_idx = idx + 1;
                        },
                        // column number and content
                        // ----------
                        2 => {
                            // column
                            // ------
                            column = std.fmt.parseInt(usize, line[start_idx..idx], 10) catch |err| {
                                filename.deinit();
                                content.deinit();
                                std.log.err("RipgrepResultsIterator: can't read column: {}", .{err});
                                return null;
                            };
                            start_idx = idx + 1;

                            // content
                            // -------
                            content.appendConst(line[start_idx..line.len]) catch |err| {
                                filename.deinit();
                                content.deinit();
                                std.log.err("RipgrepResultsIterator: can't appendConst the content: {}", .{err});
                                return null;
                            };
                            // we're done
                            break;
                        },
                        else => {
                            std.log.err("RipgrepResultsIterator: entered token {d} which should never happen.", .{token});
                            return null;
                        },
                    }

                    token += 1;
                }

                if (!it.next()) {
                    break;
                }
                idx += 1;
            }

            return RipgrepResult{
                .filename = filename,
                .content = content,
                .line_number = line_number,
                .column = column,
            };
        }
        return null;
    }
};

pub const Ripgrep = struct {
    pub fn search(allocator: std.mem.Allocator, parameters: []const u8, cwd: []const u8) !RipgrepResults {
        var args = std.ArrayListUnmanaged([]const u8).empty;
        defer args.deinit(allocator);

        try args.append(allocator, "rg");
        try args.append(allocator, "--vimgrep");
        try args.append(allocator, parameters);

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

        return RipgrepResults{
            .allocator = allocator,
            .stdout = result.stdout,
        };
    }
};
