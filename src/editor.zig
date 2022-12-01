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
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const Vec2utoi = @import("vec.zig").Vec2utoi;

pub const EditorError = error{
    NothingToUndo,
    NoSearchResult,
};

pub const SearchDirection = enum { Before, After };

/// Editor helps editing a Buffer.
/// Provides UTF8 methods to insert text, remove text, etc.
pub const Editor = struct {
    allocator: std.mem.Allocator,
    buffer: Buffer,
    has_changes_compared_to_disk: bool,
    history: std.ArrayList(Change),
    history_enabled: bool,
    history_current_block_id: i64,
    prng: std.rand.DefaultPrng,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator, buffer: Buffer) Editor {
        return Editor{
            .allocator = allocator,
            .buffer = buffer,
            .has_changes_compared_to_disk = false,
            .history = std.ArrayList(Change).init(allocator),
            .history_enabled = true,
            .history_current_block_id = 0,
            .prng = std.rand.DefaultPrng.init(1234),
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
        if (!self.history_enabled) {
            return;
        }
        self.history.append(Change{
            .block_id = self.history_current_block_id,
            .data = data,
            .pos = pos,
            .type = change_type,
        }) catch |err| {
            std.log.err("can't append to the history: {any}", .{err});
            data.deinit();
        };

        self.has_changes_compared_to_disk = true;
    }
    
    fn historyEndBlock(self: *Editor) void {
        self.history_current_block_id = self.prng.random().int(i64);
    }

    /// undo un-does the last change and all previous changes of the same type.
    /// returns the position at which should be the cursor.
    pub fn undo(self: *Editor) !Vec2u {
        if (self.history.items.len == 0 or !self.history_enabled) {
            return EditorError.NothingToUndo;
        }
        var change = self.history.pop();
        var t = change.type;
        try History.undo(self, change);
        var pos = change.pos;
        while (self.history.items.len > 0 and self.history.items[self.history.items.len - 1].type == t) {
            change = self.history.pop();
            try History.undo(self, change);
            pos = change.pos;
        }
        self.has_changes_compared_to_disk = true;
        return pos;
    }

    /// save writes the data of the current buffer into the file.
    /// Returns an error if the Editor is wrapping a Buffer not based on a file (or not containing
    /// any filepath to write to).
    /// Resets the "changed" status.
    pub fn save(self: *Editor) !void {
        try self.buffer.writeOnDisk();
        self.has_changes_compared_to_disk = false;
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

    /// deleteChunk removes chunk of text in lines.
    /// `start_pos` and `end_pos` are in glyph.
    /// Returns the new cursor position.
    pub fn deleteChunk(self: *Editor, start_pos: Vec2u, end_pos: Vec2u) !Vec2u {
        if (start_pos.b < 0 or end_pos.b >= self.buffer.lines.items.len) {
            return BufferError.OutOfBuffer;
        }

        // single line or part of a single line to delete
        // ----------------------------------------------

        if (start_pos.b == end_pos.b) {
            // delete only a piece of it
            var j: usize = start_pos.a;
            while (j < end_pos.a) : (j += 1) {
                try self.deleteGlyph(Vec2u{ .a = start_pos.a, .b = start_pos.b }, false);
            }
            return Vec2u{ .a = start_pos.a, .b = start_pos.b };
        }

        // multiple lines to delete
        // ------------------------

        var i: usize = 0;
        var line_removed: usize = 0;
        while (i <= end_pos.b) : (i += 1) {
            var line = try self.buffer.getLine(i - line_removed);
            var line_size = try line.utf8size();

            // starting line has to be complete deleted
            if (start_pos.a == 0 and i == start_pos.b and (end_pos.b > start_pos.b or end_pos.a == line_size - 1)) {
                // we have to completely delete the first line
                try self.deleteLine(start_pos.b - line_removed);
                line_removed += 1;
                continue;
            }

            // starting line only has a chunk to remove
            if (start_pos.a > 0 and i == start_pos.b) {
                // we have to partially removes data from the first line
                var j: usize = 0;
                while (j < line_size - start_pos.a) : (j += 1) {
                    try self.deleteGlyph(Vec2u{ .a = start_pos.a, .b = i - line_removed }, false);
                }
            }

            // in between lines can be simply removed
            if (i > start_pos.b and i < end_pos.b) {
                try self.deleteLine(i - line_removed);
                line_removed += 1;
            }

            // ending line only has a chunk to remove, we have to take all what's left on the end
            // line, and put it on the cursor position
            if (i == end_pos.b and end_pos.a > 0 and end_pos.a < line_size) {
                var j: usize = end_pos.a - 1;
                var k: usize = 0;

                var it = try UTF8Iterator.init(line.bytes(), j);
                while (j < line_size) : (j += 1) {
                    if (it.next()) {
                        try self.insertUtf8Text(Vec2u{ .a = start_pos.a + k, .b = start_pos.b }, it.glyph());
                    }
                    k += 1;
                }

                j = 0;
                while (j < end_pos.a) : (j += 1) {
                    try self.deleteGlyph(Vec2u{ .a = 0, .b = i - line_removed }, false);
                }

                try self.deleteLine(i - line_removed);
                line_removed += 1;
            }
        }

        return Vec2u{ .a = start_pos.a, .b = start_pos.b };
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    // TODO(remy): what happens on the very last line of the buffer/editor?
    /// `above` is a special behavior where the new line is created above the current line.
    pub fn newLine(self: *Editor, pos: Vec2u, above: bool) !void {
        if (above) {
            var new_line = U8Slice.initEmpty(self.allocator);
            self.buffer.lines.insert(pos.b, new_line) catch |err| {
                std.log.err("can't insert a new line: {}", .{err});
            };
            // TODO(remy): history entry
            self.has_changes_compared_to_disk = true;
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
        if (self.buffer.lines.items.len == 0) {
            var new_line = U8Slice.initEmpty(self.allocator);
            try self.buffer.lines.append(new_line);
        }

        var line = try self.buffer.getLine(@intCast(u64, pos.b));

        // since utf8 could be one or multiple bytes, we have to find
        // in bytes where to insert this new text in the slice.
        var insert_pos = try line.utf8pos(pos.a);

        // insert the new text
        try line.data.insertSlice(insert_pos, txt);

        var utf8_pos = Vec2u{ .a = insert_pos, .b = pos.b };
        self.historyAppend(ChangeType.InsertUtf8Char, undefined, utf8_pos);
    }

    /// deleteGlyph deletes on glyph from the underlying buffer.
    pub fn deleteGlyph(self: *Editor, pos: Vec2u, left: bool) !void {
        var line = try self.buffer.getLine(pos.b);
        if (left and pos.a == 0) {
            // TODO(remy): removing a line.
            std.log.debug("TODO(remy): removing a line", .{});
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

    /// paste pastes the content of `txt` at the given `position` in the buffer.
    /// Returns a position (in glyph) representing the end position after having
    /// pasted the `txt` content.
    // TODO(remy): unit test
    pub fn paste(self: *Editor, position: Vec2u, txt: U8Slice) !Vec2u {
        var i: usize = 0;
        var insert_pos = position;
        while (i < txt.data.items.len) {
            // new line
            if (txt.data.items[i] == '\n') {
                try self.newLine(insert_pos, false);
                insert_pos.a = 0;
                insert_pos.b += 1;
                i += 1;
                continue;
            }
            // not a new line
            var to_add: u3 = try std.unicode.utf8ByteSequenceLength(txt.data.items[i]);
            try self.insertUtf8Text(insert_pos, txt.data.items[i .. i + to_add]);
            insert_pos.a += 1;
            i += to_add;
        }
        return insert_pos;
    }

    /// search looks for the given utf8 text starting from the given position
    /// Use `before` to look before the given position instead of after.
    /// TODO(remy): unit test
    pub fn search(self: Editor, txt: U8Slice, starting_pos: Vec2u, direction: SearchDirection) !Vec2u {
        var i: usize = starting_pos.b;

        if (starting_pos.b > self.buffer.lines.items.len) {
            return EditorError.NoSearchResult;
        }

        while (i < self.buffer.lines.items.len) {
            if (self.buffer.getLine(i)) |line| {
                // check only the rest of the line if current line is the one the cursor is on
                // otherwise, it's a "new" line to check, scan it completely
                var utf8pos: usize = 0;
                if (i == starting_pos.b) {
                    if (line.utf8pos(starting_pos.a)) |pos| {
                        utf8pos = pos;
                        // if possible, we even want to move one char to the right,
                        // to look for the next possible values.
                        if (line.utf8size()) |utf8size| {
                            if (utf8pos < utf8size - 1) {
                                utf8pos += 1;
                            }
                        } else |_| {}
                    } else |_| {}
                }

                // search, if anything is found, return the result
                if (std.mem.indexOfPos(u8, line.bytes(), utf8pos, txt.bytes())) |result| {
                    return Vec2u{ .a = result, .b = i };
                }
            } else |err| {
                std.log.err("Editor.search: can't getLine: {}", .{err});
                return EditorError.NoSearchResult;
            }

            if (direction == .Before) {
                if (i == 0) {
                    return EditorError.NoSearchResult;
                } else {
                    i -= 1;
                }
            } else {
                i += 1;
            }
        }

        return EditorError.NoSearchResult;
    }

    // Others
    // ------

    /// linesCount returns how many lines is this editor's buffer.
    pub fn linesCount(self: Editor) usize {
        return self.buffer.linesCount();
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
    _ = try editor.undo();
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
    _ = try editor.undo();
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
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, false);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, false);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, false);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "o world\n"));
    _ = try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello world\n"));
    try editor.deleteGlyph(Vec2u{ .a = 6, .b = 0 }, false);
    try editor.deleteGlyph(Vec2u{ .a = 6, .b = 0 }, false);
    try editor.deleteGlyph(Vec2u{ .a = 6, .b = 0 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello ld\n"));
    try editor.deleteGlyph(Vec2u{ .a = 1, .b = 1 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "ad a second line\n"));
    try editor.deleteLine(1);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "and a third"));
    _ = try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "ad a second line\n"));
    _ = try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "and a second line\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello world\n"));
    _ = editor.undo() catch |err| {
        try expect(err == EditorError.NothingToUndo);
    };
    editor.deinit();
}

test "editor_delete_utf8_char_and_undo" {
    const allocator = std.testing.allocator;
    var editor = Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_3"));
    try expect(editor.buffer.lines.items.len == 1);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, false);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, false);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, false);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "îôûñé👻"));
    _ = try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "🎃àéîôûñé👻"));
    editor.deinit();
}
