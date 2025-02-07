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

pub fn gitDiff(allocator: std.mem.Allocator) !std.StringHashMap(std.ArrayList(GitChange)) {
    var repo: ?*c.git_repository = null;
    if (c.git_repository_open(&repo, ".") < 0) {
        // most likely no repo here
        return GitError.RepoError;
    }
    defer c.git_repository_free(repo);

    var index: ?*c.git_index = null;
    if (c.git_repository_index(&index, repo) < 0) {
        std.log.err("gitDiff: can't get index: {s}", .{c.giterr_last().*.message});
        return GitError.IndexError;
    }
    defer c.git_index_free(index);

    var diff: ?*c.git_diff = null;
    if (c.git_diff_index_to_workdir(&diff, repo, index, null) < 0) {
        std.log.err("gitDiff: can't compute diff: {s}", .{c.giterr_last().*.message});
        return GitError.DiffError;
    }
    defer c.git_diff_free(diff);

    var buf = c.git_buf{};
    if (c.git_diff_to_buf(&buf, diff, c.GIT_DIFF_FORMAT_PATCH) < 0) {
        return GitError.ToBufError;
    }

    var rv = std.StringHashMap(std.ArrayList(GitChange)).init(allocator);
    var line_it = std.mem.splitScalar(u8, buf.ptr[0..buf.size], '\n');
    while (line_it.next()) |line| {
        if (std.mem.startsWith(u8, line, "+++ b/")) {
            // starting for a new file
            const filepath = line["+++ b/".len..line.len];
            const changes = try parseForFile(allocator, &line_it);
            try rv.put(filepath, changes);
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
            try rv.append(GitChange{
                .line = line_pos - 1,
                .status = .GitRemoved,
            });
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
