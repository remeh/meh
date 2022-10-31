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
    /// `DeleteChar` is the action of having removed a character in a line.
    /// The vector `pos` contains the position of the removed character
    /// before it was removed.
    /// Deleted char is available in `ch`.
    DeleteChar,
    /// `DeleteLine` is the action of a completely deleted line.
    /// The vector `pos` contains the line at which it was before deletion.
    /// Deleted line is available in `data`.
    DeleteLine,
    /// `InsertNewLine` is the action of creating a new line by inserting a newline char.
    /// The vector `pos` contains the character position where the newline char has been inserted.
    /// There is no data in `data` or `ch`.
    InsertNewLine,
};

/// Change represents a modification of a buffer.
/// The Change owns the `data` and has to release it.
/// The `pos` vector can have different meanings depending on the `type` of the Change.
const Change = struct {
    type: ChangeType,
    data: U8Slice,
    ch: u8,
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
    fn historyAppend(self: *Editor, change_type: ChangeType, data: U8Slice, ch: u8, pos: Vec2i) void {
        self.history.append(Change{
            .ch = ch,
            .data = data,
            .pos = pos,
            .type = change_type,
        }) catch |err| {
            std.log.err("can't append to the history: {any}", .{err});
            data.deinit();
        };
    }

    // TODO(remy): comment
    fn historyUndo(self: *Editor, change: Change) !void {
        switch (change.type) {
            // TODO(remy): unit test
            .InsertNewLine => {
                var extra = try self.buffer.getLine(@intCast(u64, change.pos.b + 1));
                var line = try self.buffer.getLine(@intCast(u64, change.pos.b));
                // remove the \n
                line.data.shrinkAndFree(line.size() - 1);
                // append the rest of data
                try line.data.appendSlice(extra.bytes());
                // remove the next line which has been appended already
                var data = self.buffer.lines.orderedRemove(@intCast(usize, change.pos.b + 1)); // XXX(remy): are we sure with this +1?
                data.deinit();
            },
            .DeleteChar => {
                var line = try self.buffer.getLine(@intCast(u64, change.pos.b));
                try line.insertChar(@intCast(usize, change.pos.a), change.ch);
            },
            .DeleteLine => {
                try self.buffer.lines.insert(@intCast(usize, change.pos.a), change.data);
            },
        }
    }

    pub fn undo(self: *Editor) !void {
        if (self.history.items.len == 0) {
            return;
        }
        var change = self.history.pop();
        var t = change.type;
        try self.historyUndo(change);
        while (self.history.items.len > 0 and self.history.items[self.history.items.len - 1].type == t) {
            change = self.history.pop();
            try self.historyUndo(change);
        }
    }

    // Text edition
    // ------------

    /// deleteLine deletes the given line from the buffer.
    /// `line_pos` starts with 0
    pub fn deleteLine(self: *Editor, line_pos: usize) void {
        var deleted_line = self.buffer.lines.orderedRemove(line_pos);
        // history
        self.historyAppend(ChangeType.DeleteLine, deleted_line, 0, Vec2i{ .a = @intCast(i64, line_pos), .b = -1 });
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    // TODO(remy): what happens on the very last line of the buffer/editor?
    /// `above` is a special behavior where the new line is created above the current line.
    pub fn newLine(self: *Editor, pos: Vec2i, above: bool) !void {
        if (above) {
            // TODO(remy): history entry
            var new_line = U8Slice.initEmpty(self.allocator);
            self.buffer.lines.insert(@intCast(usize, pos.b), new_line) catch |err| {
                std.log.err("can't insert a new line: {}", .{err});
            };
        } else {
            // TODO(remy): this should be a different method (which should contain the change stuff)
            //             and this method should maybe be in the buffer itself?
            var line = try self.buffer.getLine(@intCast(u64, pos.b));
            var rest = line.data.items[@intCast(usize, pos.a)..line.size()];
            var new_line = try U8Slice.initFromSlice(self.allocator, rest);
            line.data.shrinkAndFree(@intCast(usize, pos.a));
            try line.data.append('\n');
            try self.buffer.lines.insert(@intCast(usize, pos.b) + 1, new_line);
            // history
            self.historyAppend(ChangeType.InsertNewLine, undefined, 0, pos);
        }
    }

    // TODO(remy): comment
    pub fn deleteChar(self: *Editor, pos: Vec2i, go_left: bool) !void {
        if (go_left) {} else {
            var line = try self.buffer.getLine(@intCast(u64, pos.b));
            var ch = line.data.orderedRemove(@intCast(usize, pos.a));
            // history
            self.historyAppend(ChangeType.DeleteChar, undefined, ch, pos);
        }
    }
};

test "editor_new_line_and_undo" {
    const allocator = std.testing.allocator;
    var editor = Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_2"));
    try expect(editor.buffer.lines.items.len == 3);
    try editor.newLine(Vec2i{ .a = 3, .b = 1 }, false);
    try expect(editor.buffer.lines.items.len == 4);
    var line = (try editor.buffer.getLine(2)).bytes();
    std.log.debug("{s}", .{line});
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(2)).bytes(), " a second line\n"));
    try editor.newLine(Vec2i{ .a = 0, .b = 2 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(2)).bytes(), "\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(3)).bytes(), " a second line\n"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and a second line\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(2)).bytes(), "and a third"));
    editor.deinit();
}

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
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and a second line\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(2)).bytes(), "and a third"));
    try expect(editor.buffer.lines.items.len == 3);
    editor.deinit();
}

test "editor_delete_char_and_undo" {
    const allocator = std.testing.allocator;
    var editor = Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_2"));
    try expect(editor.buffer.lines.items.len == 3);
    try editor.deleteChar(Vec2i{ .a = 0, .b = 0 }, false);
    try editor.deleteChar(Vec2i{ .a = 0, .b = 0 }, false);
    try editor.deleteChar(Vec2i{ .a = 0, .b = 0 }, false);
    try editor.deleteChar(Vec2i{ .a = 0, .b = 0 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "o world\n"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello world\n"));
    try editor.deleteChar(Vec2i{ .a = 6, .b = 0 }, false);
    try editor.deleteChar(Vec2i{ .a = 6, .b = 0 }, false);
    try editor.deleteChar(Vec2i{ .a = 6, .b = 0 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello ld\n"));
    try editor.deleteChar(Vec2i{ .a = 1, .b = 1 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "ad a second line\n"));
    editor.deleteLine(1);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "and a third"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "ad a second line\n"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "and a second line\n"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello world\n"));
    editor.deinit();
}
