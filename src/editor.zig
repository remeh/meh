const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const Buffer = @import("buffer.zig").Buffer;
const ImVec2 = @import("vec.zig").ImVec2;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;

// TODO(remy): comment
const ChangeType = enum {
    AddBlock,
    DeleteBlock,
    /// `DeleteLine`  is the action of a completely deleted line.
    /// The vector `pos` contains the line at which it was before deletion.
    DeleteLine,
};

/// Change represents a modification of a buffer.
/// The Change owns the `data` and has to release it.
/// The `pos` vector can have different meanings depending on the `type` of the Change.
const Change = struct {
    type: ChangeType,
    data: U8Slice,
    /// depending on the `change_type`, only the first field of the
    /// vector could be used (for instance for a line action).
    pos: Vec2i,
};

// TODO(remy): comment
pub const Editor = struct {
    allocator: std.mem.Allocator,
    buffer: Buffer,
    history: std.ArrayList(Change),

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator, buffer: Buffer) Editor {
        return Editor{
            .allocator = allocator,
            .buffer = buffer,
            .history = std.ArrayList(Change).init(allocator),
        };
    }

    pub fn deinit(self: *Editor) void {
        for (self.history.items) |change| {
            change.data.deinit();
        }
        self.history.deinit();
        self.buffer.deinit();
    }

    // History
    // -------

    /// historyAppend appends a new entry in the history.
    /// If the append fails, the memory is deleted to avoid any leak.
    fn historyAppend(self: *Editor, change_type: ChangeType, data: U8Slice, pos: Vec2i) void {
        self.history.append(Change{
            .type = change_type,
            .data = data,
            .pos = pos,
        }) catch |err| {
            std.log.err("can't append to the history: {any}", .{err});
            data.deinit();
        };
    }

    // TODO(remy): comment
    fn historyUndo(self: *Editor, change: Change) !void {
        switch (change.type) {
            .DeleteLine => {
                try self.buffer.lines.insert(@intCast(usize, change.pos.a), change.data);
            },
            else => {},
        }
    }

    // Text edition
    // ------------

    pub fn undo(self: *Editor) !void {
        if (self.history.items.len == 0) {
            return;
        }
        var change = self.history.pop();
        try self.historyUndo(change);
    }

    /// deleteLine deletes the given line from the buffer.
    /// `line_pos` starts with 0
    pub fn deleteLine(self: *Editor, line_pos: usize) void {
        var deleted_line = self.buffer.lines.orderedRemove(line_pos);
        self.historyAppend(ChangeType.DeleteLine, deleted_line, Vec2i{ .a = @intCast(i64, line_pos), .b = -1 });
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    // TODO(remy): what happens on the very last line of the buffer/editor?
    pub fn newLine(self: *Editor, pos: Vec2i, after: bool) void {
        if (after) {
            var line = self.buffer.getLine(@intCast(u64, pos.b)) catch |err| {
                std.log.err("Editor.newLine: {}", .{err});
                return;
            };
            var rest = line.data.items[@intCast(usize, pos.a)..line.size()];
            // TODO(remy): this should be a different method (which should contain the change stuff)
            line.data.shrinkAndFree(@intCast(usize, pos.a + 1));
            var new_line = U8Slice.initFromSlice(self.allocator, rest) catch |err| {
                std.log.err("Editor.newLine: can't create a new U8Slice: {}", .{err});
                return;
            };
            self.buffer.lines.insert(@intCast(usize, pos.b) + 1, new_line) catch |err| {
                std.log.err("Editor.newLine: can't insert a new line: {}", .{err});
            };
        } else {
            var new_line = U8Slice.initEmpty(self.allocator);
            self.buffer.lines.insert(@intCast(usize, pos.b), new_line) catch |err| {
                std.log.err("can't insert a new line: {}", .{err});
            };
        }
    }
};

test "editor_delete_line_and_undo" {
    const allocator = std.testing.allocator;
    var editor = Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_2"));
    try expect(editor.buffer.lines.items.len == 3);
    editor.deleteLine(0);
    try expect(editor.buffer.lines.items.len == 2);
    editor.deleteLine(0);
    try expect(editor.buffer.lines.items.len == 1);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "and a third"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "and a second line\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and a third"));
    try expect(editor.buffer.lines.items.len == 2);
    editor.deinit();
}
