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
    /// It's vector `pos` contains the line at which it was before deletion.
    DeleteLine,
};

// TODO(remy): comment
const Change = struct {
    type: ChangeType,
    data: U8Slice,
    /// depending on the `change_type`, only the first field of the
    /// vector could be used (for instance for a line action).
    pos: Vec2i,
};

// TODO(remy): comment
pub const Editor = struct {
    buffer: Buffer,
    history: std.ArrayList(Change),

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator, buffer: Buffer) Editor {
        return Editor{
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

    /// historyAppend has to be used to append a new entry in the history.
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
};

test "editor_delete_line" {
    const allocator = std.testing.allocator;
    var editor = Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_2"));
    try expect(editor.buffer.lines.items.len == 3);
    editor.deleteLine(0);
    try expect(editor.buffer.lines.items.len == 2);
    editor.deleteLine(0);
    try expect(editor.buffer.lines.items.len == 1);
    try editor.undo();
    try expect(editor.buffer.lines.items.len == 2);
    editor.deinit();
}
