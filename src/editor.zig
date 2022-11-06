const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const Buffer = @import("buffer.zig").Buffer;
const BufferError = @import("buffer.zig").BufferError;
const Change = @import("history.zig").Change;
const ChangeType = @import("history.zig").ChangeType;
const History = @import("history.zig").History;
const ImVec2 = @import("vec.zig").ImVec2;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;

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
    fn historyAppend(self: *Editor, change_type: ChangeType, data: U8Slice, pos: Vec2u) void {
        self.history.append(Change{
            .data = data,
            .pos = pos,
            .type = change_type,
        }) catch |err| {
            std.log.err("can't append to the history: {any}", .{err});
            data.deinit();
        };
    }

    pub fn undo(self: *Editor) !void {
        if (self.history.items.len == 0) {
            return;
        }
        var change = self.history.pop();
        var t = change.type;
        try History.undo(self, change);
        while (self.history.items.len > 0 and self.history.items[self.history.items.len - 1].type == t) {
            change = self.history.pop();
            try History.undo(self, change);
        }
    }

    // Text edition
    // ------------

    /// deleteLine deletes the given line from the buffer.
    /// `line_pos` starts with 0
    pub fn deleteLine(self: *Editor, line_pos: usize) !void {
        if (line_pos < 0 or line_pos >= self.buffer.lines.items.len) {
            return BufferError.OutOfBuffer;
        }

        var deleted_line = self.buffer.lines.orderedRemove(line_pos);
        // history
        self.historyAppend(ChangeType.DeleteLine, deleted_line, Vec2u{ .a = 0, .b = line_pos });
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    // TODO(remy): what happens on the very last line of the buffer/editor?
    /// `above` is a special behavior where the new line is created above the current line.
    pub fn newLine(self: *Editor, pos: Vec2u, above: bool) !void {
        if (above) {
            // TODO(remy): history entry
            var new_line = U8Slice.initEmpty(self.allocator);
            self.buffer.lines.insert(pos.b, new_line) catch |err| {
                std.log.err("can't insert a new line: {}", .{err});
            };
        } else {
            var line = try self.buffer.getLine(pos.b);
            var rest = line.data.items[try line.utf8pos(pos.a)..line.size()];
            var new_line = try U8Slice.initFromSlice(self.allocator, rest);
            line.data.shrinkAndFree(try line.utf8pos(pos.a));
            try line.data.append('\n');
            try self.buffer.lines.insert(pos.b + 1, new_line);
            // history
            self.historyAppend(ChangeType.InsertNewLine, undefined, pos);
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    /// `txt` must be in utf8.
    pub fn insertUtf8Text(self: *Editor, pos: Vec2u, txt: []const u8) !void {
        var line = try self.buffer.getLine(@intCast(u64, pos.b));

        // since utf8 could be one or multiple bytes, we have to find
        // in bytes where to insert this new text in the slice.
        var insert_pos = try line.utf8pos(pos.a);

        // insert the new text
        try line.data.insertSlice(insert_pos, txt);

        var utf8_pos = Vec2u{ .a = insert_pos, .b = pos.b };
        self.historyAppend(ChangeType.InsertUtf8Char, undefined, utf8_pos);
    }

    // TODO(remy): comment
    pub fn deleteUtf8Char(self: *Editor, pos: Vec2u, left: bool) !void {
        var line = try self.buffer.getLine(pos.b);
        if (left and pos.a == 0) {
            // TODO(remy): removing a line.
        } else if (!left and pos.a == line.data.items.len - 1) {
            // TODO(remy): merging the line.
        } else {
            var remove_pos: usize = 0;
            if (left) {
                remove_pos = try line.utf8pos(pos.a - 1);
            } else {
                remove_pos = try line.utf8pos(pos.a);
            }
            // how many bytes to remove
            var to_remove: u3 = try std.unicode.utf8ByteSequenceLength(line.data.items[remove_pos]);
            var removed = U8Slice.initEmpty(self.allocator);
            while (to_remove > 0) : (to_remove -= 1) {
                var ch = line.data.orderedRemove(remove_pos);
                try removed.data.append(ch);
            }

            var utf8_pos = Vec2u{ .a = remove_pos, .b = pos.b };
            self.historyAppend(ChangeType.DeleteUtf8Char, removed, utf8_pos);
        }
    }
};

test "editor_new_line_and_undo" {
    const allocator = std.testing.allocator;
    var editor = Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_2"));
    try expect(editor.buffer.lines.items.len == 3);
    try editor.newLine(Vec2u{ .a = 3, .b = 1 }, false);
    try expect(editor.buffer.lines.items.len == 4);
    var line = (try editor.buffer.getLine(2)).bytes();
    std.log.debug("{s}", .{line});
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(2)).bytes(), " a second line\n"));
    try editor.newLine(Vec2u{ .a = 0, .b = 2 }, false);
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
    try editor.deleteLine(0);
    try expect(editor.buffer.lines.items.len == 2);
    try editor.deleteLine(0);
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
    try editor.deleteUtf8Char(Vec2u{ .a = 0, .b = 0 }, false);
    try editor.deleteUtf8Char(Vec2u{ .a = 0, .b = 0 }, false);
    try editor.deleteUtf8Char(Vec2u{ .a = 0, .b = 0 }, false);
    try editor.deleteUtf8Char(Vec2u{ .a = 0, .b = 0 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "o world\n"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello world\n"));
    try editor.deleteUtf8Char(Vec2u{ .a = 6, .b = 0 }, false);
    try editor.deleteUtf8Char(Vec2u{ .a = 6, .b = 0 }, false);
    try editor.deleteUtf8Char(Vec2u{ .a = 6, .b = 0 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello ld\n"));
    try editor.deleteUtf8Char(Vec2u{ .a = 1, .b = 1 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "ad a second line\n"));
    try editor.deleteLine(1);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "and a third"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "ad a second line\n"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "and a second line\n"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello world\n"));
    editor.deinit();
}

test "editor_delete_utf8_char_and_undo" {
    const allocator = std.testing.allocator;
    var editor = Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_3"));
    try expect(editor.buffer.lines.items.len == 1);
    try editor.deleteUtf8Char(Vec2u{ .a = 0, .b = 0 }, false);
    try editor.deleteUtf8Char(Vec2u{ .a = 0, .b = 0 }, false);
    try editor.deleteUtf8Char(Vec2u{ .a = 0, .b = 0 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "îôûñé👻"));
    try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "🎃àéîôûñé👻"));
    editor.deinit();
}
