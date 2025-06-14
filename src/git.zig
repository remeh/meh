const std = @import("std");
const c = @import("clib.zig").c;

const Buffer = @import("buffer.zig").Buffer;
const LineStatusType = @import("widget_text_edit.zig").LineStatusType;
const U8Slice = @import("u8slice.zig").U8Slice;

pub const GitChange = struct {
    line: usize,
    status: LineStatusType,
};

pub const GitError = error{
    RepoError,
    IndexError,
    DiffError,
    ToBufError,
};

pub fn cmdGitDiff(allocator: std.mem.Allocator, filepath: []const u8, cwd: []const u8) !std.StringHashMap(std.ArrayList(GitChange)) {
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    try args.append("git");
    try args.append("diff");
    try args.append(filepath);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = args.items,
        .cwd = cwd,
        .max_output_bytes = 25 * 1024 * 1024,
    });
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }

    var rv = std.StringHashMap(std.ArrayList(GitChange)).init(allocator);
    var line_it = std.mem.splitScalar(u8, result.stdout.ptr[0..result.stdout.len], '\n');
    while (line_it.next()) |line| {
        if (std.mem.startsWith(u8, line, "+++ b/")) {
            // starting for a new file
            const git_file: []u8 = try allocator.alloc(u8, (line.len - "+++ b/".len));
            std.mem.copyForwards(u8, git_file, line["+++ b/".len..line.len]);
            const changes = try parseForFile(allocator, &line_it);
            try rv.put(git_file, changes);
        }
    }
    return rv;
}

fn parseForFile(allocator: std.mem.Allocator, line_it: *std.mem.SplitIterator(u8, .scalar)) !std.ArrayList(GitChange) {
    var rv = std.ArrayList(GitChange).init(allocator);
    var line_pos: u32 = 0;
    while (line_it.*.next()) |line| {
        if (std.mem.startsWith(u8, line, "diff --git a/")) {
            // we're done for this file
            break;
        } else if (std.mem.startsWith(u8, line, "@@ -")) {
            // we're looking at a chunk of change in this file, capture where it starts
            if (std.mem.indexOf(u8, line, " +")) |start| {
                if (std.mem.indexOf(u8, line[start..], ",")) |comma| {
                    const idx = start + " +".len;
                    const line_pos_str = line[idx .. idx + comma - 2];
                    line_pos = try std.fmt.parseInt(u32, line_pos_str, 10);
                }
            }
        } else if (std.mem.startsWith(u8, line, "-")) {
            if (line_pos > 0) {
                try rv.append(GitChange{
                    .line = line_pos - 1,
                    .status = .GitRemoved,
                });
            }
            continue;
        } else if (std.mem.startsWith(u8, line, "+")) {
            try rv.append(GitChange{
                .line = line_pos - 1,
                .status = .GitAdded,
            });
            line_pos += 1;
        } else {
            line_pos += 1;
        }
    }
    return rv;
}
