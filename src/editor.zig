const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const Buffer = @import("buffer.zig").Buffer;
const BufferError = @import("buffer.zig").BufferError;
const Change = @import("history.zig").Change;
const ChangeType = @import("history.zig").ChangeType;
const History = @import("history.zig").History;
const GitChange = @import("git.zig").GitChange;
const LSP = @import("lsp.zig").LSP;
const SyntaxHighlighter = @import("syntax_highlighter.zig").SyntaxHighlighter;
const U8Slice = @import("u8slice.zig").U8Slice;
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const Vec2utoi = @import("vec.zig").Vec2utoi;

pub const EditorError = error{
    NothingToUndo,
    NoSearchResult,
    NoWordHere,
};

pub const Triggerer = enum {
    Input,
    Paste,
    Redo,
    Undo,
};

pub const SearchDirection = enum { Before, After };
pub const DeleteDirection = enum { Left, Right };

pub const punctuation = ",./&\"'[|]{}()-=:;<>*!?@#+~` \t\n";

/// Editor helps editing a Buffer.
/// Provides UTF8 methods to insert text, remove text, history support, etc.
pub const Editor = struct {
    allocator: std.mem.Allocator,
    buffer: Buffer,
    lsp: ?*LSP,
    has_changes_compared_to_disk: bool,
    history: std.ArrayListUnmanaged(Change),
    history_redo: std.ArrayListUnmanaged(Change),
    history_enabled: bool,
    history_current_block_id: i64,
    prng: std.Random.DefaultPrng,
    syntax_highlighter: SyntaxHighlighter,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator, buffer: Buffer) !Editor {
        return Editor{
            .allocator = allocator,
            .buffer = buffer,
            .has_changes_compared_to_disk = false,
            .history = std.ArrayListUnmanaged(Change).empty,
            .history_redo = std.ArrayListUnmanaged(Change).empty,
            .history_enabled = true,
            .history_current_block_id = 0,
            .lsp = null,
            .prng = std.Random.DefaultPrng.init(1234),
            .syntax_highlighter = try SyntaxHighlighter.init(allocator, buffer.linesCount()),
        };
    }

    pub fn deinit(self: *Editor) void {
        self.syntax_highlighter.deinit();
        for (self.history.items) |*change| {
            change.data.deinit();
        }
        for (self.history_redo.items) |*change| {
            change.data.deinit();
        }
        self.history.deinit(self.allocator);
        self.history_redo.deinit(self.allocator);
        self.buffer.deinit();
    }

    // History
    // -------

    /// historyAppend appends a new entry in the history.
    /// If the append fails, the memory is deleted to avoid any leak.
    fn historyAppend(self: *Editor, change_type: ChangeType, data: U8Slice, pos: Vec2u, triggerer: Triggerer) void {
        if (!self.history_enabled) {
            data.deinit();
            return;
        }

        if (triggerer == .Undo) {
            data.deinit();
            return;
        }

        // on input, we want to clear the redo list because
        // it doesn't make any sense anymore.
        if (triggerer == .Input) {
            while (self.history_redo.pop()) |change| {
                change.deinit();
            }
        }

        self.history.append(self.allocator, Change{
            .block_id = self.history_current_block_id,
            .data = data,
            .pos = pos,
            .type = change_type,
        }) catch |err| {
            std.log.err("can't append to the history: {}", .{err});
            data.deinit();
        };

        self.has_changes_compared_to_disk = true;
    }

    /// historyEndBlock indicates that next changes won't have to be undo
    /// at once with the ones having happened before.
    pub fn historyEndBlock(self: *Editor) void {
        self.history_current_block_id = self.prng.random().int(i64);
    }

    /// undo un-does the last change and all previous changes of the same type.
    /// returns the position at which should be the cursor.
    pub fn undo(self: *Editor) !Vec2u {
        if (self.history.items.len == 0 or !self.history_enabled) {
            return EditorError.NothingToUndo;
        }

        var change = self.history.pop().?;
        const block_id = change.block_id;
        try change.undo(self);
        try self.history_redo.append(self.allocator, change);
        var pos = change.pos;

        while (self.history.items.len > 0 and self.history.items[self.history.items.len - 1].block_id == block_id) {
            change = self.history.pop().?;
            try change.undo(self);
            try self.history_redo.append(self.allocator, change);
            pos = change.pos;
        }

        if (self.lsp) |lsp| { // refresh the whole document
            try lsp.didChangeComplete(&self.buffer);
        }

        self.has_changes_compared_to_disk = true;

        return pos;
    }

    pub fn redo(self: *Editor) !Vec2u {
        if (self.history_redo.items.len == 0 or !self.history_enabled) {
            return EditorError.NothingToUndo;
        }

        var change = self.history_redo.pop().?;
        const block_id = change.block_id;
        try change.redo(self);
        var pos = change.pos;
        change.deinit();

        while (self.history_redo.items.len > 0 and self.history_redo.items[self.history_redo.items.len - 1].block_id == block_id) {
            change = self.history_redo.pop().?;
            try change.redo(self);
            pos = change.pos;
            change.deinit();
        }

        self.historyEndBlock();
        self.has_changes_compared_to_disk = true;

        if (self.lsp) |lsp| {
            // refresh the whole document
            try lsp.didChangeComplete(&self.buffer);
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
    /// `line_pos` starts with 0 (i.e. 0 is the first line of the buffer).
    pub fn deleteLine(self: *Editor, line_pos: usize, triggerer: Triggerer) void {
        if (line_pos < 0 or line_pos >= self.buffer.lines.items.len) {
            std.log.warn("Editor.deleteLine: can't delete line {d}, out of buffer", .{line_pos});
            return;
        }
        const deleted_line = self.buffer.lines.orderedRemove(line_pos);

        // history
        self.historyAppend(ChangeType.DeleteLine, deleted_line, Vec2u{ .a = 0, .b = line_pos }, triggerer);

        if (self.lsp) |lsp| {
            if (triggerer == .Input) {
                lsp.didChangeComplete(&self.buffer) catch |err| {
                    std.log.err("Editor.deleteLine: can't send didChange message to the LSP: {}", .{err});
                };
            }
        }

        self.syntax_highlighter.removeLine(line_pos);
    }

    /// deleteAfter deletes all glyphs after the given position (included) in the given line.
    /// Does not delete the line return of the line.
    pub fn deleteAfter(self: *Editor, position: Vec2u) void {
        if (position.b < 0 or position.b >= self.buffer.lines.items.len) {
            std.log.warn("Editor.deleteAfter: can't delete data in line {d}, out of buffer", .{position.b});
            return;
        }

        var line = self.buffer.getLine(position.b) catch |err| {
            std.log.err("Editor.deleteAfter: can't get line: {}", .{err});
            return;
        };

        const line_size = line.utf8size() catch |err| {
            std.log.err("Editor.deleteAfter: can't compute line size: {}", .{err});
            return;
        };

        var end_position = position;
        end_position.a = line_size;
        if (end_position.a > 0 and line.data.items[end_position.a - 1] == '\n') {
            // we don't want to delete the line return
            end_position.a -= 1;
        }

        _ = self.deleteChunk(position, end_position, .Input) catch |err| {
            std.log.err("Editor.deleteAfter: can't delete chunk: {}", .{err});
            return;
        };
    }

    /// deleteChunk removes chunk of text in lines.
    /// `start_pos` and `end_pos` are in glyph.
    /// Returns the new cursor position.
    pub fn deleteChunk(self: *Editor, start_pos: Vec2u, end_pos: Vec2u, triggerer: Triggerer) !Vec2u {
        if (start_pos.b < 0 or end_pos.b >= self.buffer.lines.items.len) {
            return BufferError.OutOfBuffer;
        }

        // single line or part of a single line to delete
        // ----------------------------------------------

        if (start_pos.b == end_pos.b) {
            // delete only a piece of it
            var j: usize = start_pos.a;
            while (j < end_pos.a) : (j += 1) {
                try self.deleteGlyph(Vec2u{ .a = start_pos.a, .b = start_pos.b }, .Right, triggerer);
            }
            return Vec2u{ .a = start_pos.a, .b = start_pos.b };
        }

        // only full lines are selected, we want to delete
        // all of them completely
        // -----------------------------------------------

        if (start_pos.a == 0 and end_pos.a == 0) {
            var i: usize = start_pos.b;
            while (i < end_pos.b) : (i += 1) {
                self.deleteLine(start_pos.b, triggerer);
            }
            return Vec2u{ .a = start_pos.a, .b = start_pos.b };
        }

        // multiple lines to deal with
        // ---------------------------

        var i: usize = start_pos.b;
        var line_removed: usize = 0;
        while (i <= end_pos.b) : (i += 1) {
            var line = try self.buffer.getLine(i - line_removed);
            const line_size = try line.utf8size();

            // starting line has to be completely cleaned
            if (i == start_pos.b and start_pos.a == 0 and (end_pos.b > start_pos.b or end_pos.a == line_size - 1)) {
                self.deleteLine(i - line_removed, triggerer);
                line_removed += 1;
                continue;
            }

            // starting line only has a chunk to remove
            if (i == start_pos.b and start_pos.a > 0) {
                // we have to partially removes data from the first line
                var j: usize = 0;
                while (j < line_size - start_pos.a) : (j += 1) {
                    try self.deleteGlyph(Vec2u{ .a = start_pos.a, .b = i - line_removed }, .Right, triggerer);
                }
            }

            // in between lines can be simply removed
            if (i > start_pos.b and i < end_pos.b) {
                self.deleteLine(i - line_removed, triggerer);
                line_removed += 1;
                continue;
            }

            if (i == end_pos.b) {
                // last line has to be completely removed
                if (end_pos.a == line_size - 1) {
                    self.deleteLine(end_pos.b - line_removed, triggerer);
                    line_removed += 1;
                    continue;
                }

                // last line has only a part of it which is removed
                // first, remove that chunk
                var j: usize = 0;
                while (j < end_pos.a) : (j += 1) {
                    try self.deleteGlyph(Vec2u{ .a = 0, .b = end_pos.b - line_removed }, .Right, triggerer);
                }

                if (start_pos.a > 0) {
                    // then, copy what's left on top of the cursor
                    try self.insertUtf8Text(Vec2u{ .a = start_pos.a, .b = start_pos.b }, line.bytes(), triggerer);

                    // remove the line we copied data from
                    self.deleteLine(end_pos.b - line_removed, triggerer);
                }
            }
        }

        // lsp
        if (self.lsp) |lsp| {
            if (triggerer == .Input) {
                try lsp.didChange(&self.buffer, Vec2u{ .a = start_pos.b, .b = end_pos.b });
            }
        }

        // syntax highlighting
        self.syntax_highlighter.setDirty(Vec2u{ .a = start_pos.b, .b = end_pos.b });

        return Vec2u{ .a = start_pos.a, .b = start_pos.b };
    }

    /// newLine creates a new line at the given position. Inserting the new line char to the current
    /// line and inserting a new line (U8Slice) in the buffer.
    pub fn newLine(self: *Editor, pos: Vec2u, triggerer: Triggerer) !void {
        var line = try self.buffer.getLine(pos.b);
        const rest = line.data.items[try line.utf8pos(pos.a)..line.size()];
        const new_line = try U8Slice.initFromSlice(self.allocator, rest);
        line.data.shrinkAndFree(line.allocator, try line.utf8pos(pos.a));
        try line.append('\n');
        try self.buffer.lines.insert(self.buffer.allocator, pos.b + 1, new_line);

        // history
        self.historyAppend(ChangeType.InsertNewLine, U8Slice.initEmpty(self.allocator), pos, triggerer);

        // lsp
        if (self.lsp) |lsp| {
            if (triggerer == .Input) {
                lsp.didChangeComplete(&self.buffer) catch |err| {
                    std.log.err("Editor.newLine: can't send didChange message to the LSP: {}", .{err});
                };
            }
        }

        // syntax highlighting
        try self.syntax_highlighter.insertNewLine(pos.b);
    }

    pub fn appendNextLine(self: *Editor, pos: Vec2u) !void {
        if (pos.b == self.buffer.linesCount() - 1) {
            return;
        }

        const current_line = try self.buffer.getLine(pos.b);
        const end_of_current_line = try current_line.utf8size();
        const next_line = try self.buffer.getLine(pos.b + 1);

        // remove first space chars
        var to_append = try U8Slice.initFromChar(self.allocator, ' ');
        defer to_append.deinit();
        var start: bool = true;
        for (next_line.data.items) |ch| {
            if (start and (ch == ' ' or ch == '\t')) {
                continue;
            }
            if (ch == '\n') {
                break;
            }
            start = false;
            try to_append.data.append(to_append.allocator, ch);
        }

        try self.insertUtf8Text(Vec2u{ .a = end_of_current_line - 1, .b = pos.b }, to_append.bytes(), .Input);
        self.deleteLine(pos.b + 1, .Input);
    }

    /// insertUtf8Text inserts the given UTF8 `text` at the given position.
    pub fn insertUtf8Text(self: *Editor, pos: Vec2u, txt: []const u8, triggerer: Triggerer) !void {
        if (self.buffer.lines.items.len == 0) {
            const new_line = U8Slice.initEmpty(self.allocator);
            try self.buffer.lines.append(self.buffer.allocator, new_line);
            try self.syntax_highlighter.insertNewLine(0);
        }

        var line = try self.buffer.getLine(@as(u64, @intCast(pos.b)));

        // since utf8 could be one or multiple bytes, we have to find
        // in bytes where to insert this new text in the slice.
        const insert_pos = try line.utf8pos(pos.a);

        // insert the new text
        try line.data.insertSlice(line.allocator, insert_pos, txt);

        // history
        self.historyAppend(ChangeType.InsertUtf8Text, try U8Slice.initFromSlice(self.allocator, txt), pos, triggerer);

        // lsp
        if (self.lsp) |lsp| {
            if (triggerer == .Input) {
                try lsp.didChange(&self.buffer, Vec2u{ .a = pos.b, .b = pos.b });
            }
        }

        // syntax highlighting
        self.syntax_highlighter.setDirty(Vec2u{ .a = pos.b, .b = pos.b });
    }

    /// deleteGlyph deletes on glyph from the underlying buffer.
    pub fn deleteGlyph(self: *Editor, pos: Vec2u, direction: DeleteDirection, triggerer: Triggerer) !void {
        var line = try self.buffer.getLine(pos.b);
        if (direction == .Left and pos.a == 0) {
            if (pos.b != 0) {
                // TODO(remy): removing a line.
                std.log.debug("TODO(remy): removing a line", .{});
            }
        } else {
            var remove_pos: usize = 0;
            if (direction == .Left) {
                remove_pos = try line.utf8pos(pos.a - 1);
            } else {
                remove_pos = try line.utf8pos(pos.a);
            }

            if (remove_pos >= line.data.items.len) {
                std.log.err("Editor.deleteGlyph: trying to remove glyph at byte pos: {d} while line has byte length: {d}", .{ remove_pos, line.data.items.len });
                return BufferError.OutOfBuffer;
            }

            // how many bytes to remove
            var to_remove: u3 = try std.unicode.utf8ByteSequenceLength(line.data.items[remove_pos]);
            var removed = U8Slice.initEmpty(self.allocator);
            while (to_remove > 0) : (to_remove -= 1) {
                const ch = line.data.orderedRemove(remove_pos);
                try removed.append(ch);
            }

            const utf8_pos = Vec2u{ .a = remove_pos, .b = pos.b };
            self.historyAppend(ChangeType.DeleteGlyph, removed, utf8_pos, triggerer);

            if (self.lsp) |lsp| {
                if (triggerer == .Input) {
                    try lsp.didChange(&self.buffer, Vec2u{ .a = pos.b, .b = pos.b });
                }
            }

            // syntax highlighting
            self.syntax_highlighter.setDirty(Vec2u{ .a = pos.b, .b = pos.b });
        }
    }

    /// paste pastes the content of `txt` at the given `position` in the buffer.
    /// Returns a position (in glyph) representing the end position after having
    /// pasted the `txt` content.
    pub fn paste(self: *Editor, position: Vec2u, txt: U8Slice) !Vec2u {
        var i: usize = 0;
        var insert_pos = position;
        while (i < txt.data.items.len) {
            // new line
            if (txt.data.items[i] == '\n') {
                try self.newLine(insert_pos, .Paste);
                insert_pos.a = 0;
                insert_pos.b += 1;
                i += 1;
                continue;
            }
            // not a new line
            const to_add: u3 = try std.unicode.utf8ByteSequenceLength(txt.data.items[i]);
            try self.insertUtf8Text(insert_pos, txt.data.items[i .. i + to_add], .Paste);
            insert_pos.a += 1;
            i += to_add;
        }

        if (self.lsp) |lsp| {
            try lsp.didChangeComplete(&self.buffer);
        }

        return insert_pos;
    }

    /// wordPosAt returns the start and end in the line of the word at the given `position`.
    /// Returns the start and end position of the word in the given line.
    pub fn wordPosAt(self: Editor, position: Vec2u) !Vec2u {
        if (position.b > self.buffer.lines.items.len) {
            return BufferError.OutOfBuffer;
        }

        var rv = Vec2u{ .a = position.a, .b = position.a };
        var line = try self.buffer.getLine(position.b);

        // right
        var it = try UTF8Iterator.init(line.bytes(), position.a);
        while (true) {
            if (std.mem.indexOf(u8, punctuation, it.glyph())) |pos| {
                if (pos >= 0) {
                    break;
                }
            }

            rv.b += 1;

            if (!it.next()) {
                break;
            }
        }
        // left
        it = try UTF8Iterator.init(line.bytes(), position.a);
        while (true) {
            const it_pos = it.current_byte;
            it.prev();
            if (it_pos == it.current_byte) {
                break;
            }

            if (std.mem.indexOf(u8, punctuation, it.glyph())) |pos| {
                if (pos >= 0) {
                    break;
                }
            }

            rv.a -= 1;
        }

        return rv;
    }

    /// wordAt returns the current word under the cursor.
    /// It returns it as a part of the managed line, the memory
    /// is owned by the WidgetTextEdit and should not be freed by
    /// the caller.
    pub fn wordAt(self: Editor, position: Vec2u) ![]const u8 {
        const pos = try self.wordPosAt(position);
        if (pos.a == pos.b) {
            return EditorError.NoWordHere;
        }

        var line = try self.buffer.getLine(position.b);
        if (pos.b >= line.size()) {
            return EditorError.NoWordHere;
        }

        return line.bytes()[pos.a..pos.b];
    }

    /// findGlyphInLine returns next or previous position of the given glyph (starting at
    /// the given `start_pos`.
    pub fn findGlyphInLine(self: Editor, start_pos: Vec2u, glyph: []const u8, direction: SearchDirection) !Vec2u {
        if (direction == .Before and start_pos.a == 0) {
            return Vec2u{ .a = start_pos.a, .b = start_pos.b };
        }

        var line = try self.buffer.getLine(start_pos.b);

        if (direction == .After) {
            // right
            var it = try UTF8Iterator.init(line.bytes(), start_pos.a);
            var idx: usize = start_pos.a;
            while (true) {
                if (!it.next()) {
                    return start_pos;
                }

                idx += 1;

                if (std.mem.eql(u8, it.glyph(), glyph)) {
                    return Vec2u{ .a = idx, .b = start_pos.b };
                }
            }
        } else {
            // left
            var it = try UTF8Iterator.init(line.bytes(), start_pos.a);
            var idx: usize = start_pos.a;
            while (true) {
                const current_byte = it.current_byte;
                it.prev();
                if (it.current_byte == current_byte) {
                    return start_pos;
                }

                idx -= 1;

                if (std.mem.eql(u8, it.glyph(), glyph)) {
                    return Vec2u{ .a = idx, .b = start_pos.b };
                }
            }
        }

        return start_pos;
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

test "editor insert utf8 and undo/redo" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_5"));

    try editor.insertUtf8Text(Vec2u{ .a = 0, .b = 9 }, "this is a test", .Input);
    var line = try editor.buffer.getLine(9);
    try expect(std.mem.eql(u8, line.bytes(), "this is a test\n"));

    var cursor = try editor.undo();
    try expect(cursor.a == 0);
    try expect(cursor.b == 9);
    try expect(std.mem.eql(u8, line.bytes(), "\n"));

    cursor = try editor.redo();
    try expect(cursor.a == 0);
    try expect(cursor.b == 9);
    try expect(std.mem.eql(u8, line.bytes(), "this is a test\n"));

    editor.deinit();
}

test "editor new_line and undo/redo" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_2"));
    try expect(editor.buffer.lines.items.len == 3);
    try editor.newLine(Vec2u{ .a = 3, .b = 1 }, .Input);
    try expect(editor.buffer.lines.items.len == 4);
    const line = (try editor.buffer.getLine(2)).bytes();
    std.log.debug("{s}", .{line});
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(2)).bytes(), " a second line\n"));
    try editor.newLine(Vec2u{ .a = 0, .b = 2 }, .Input);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(2)).bytes(), "\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(3)).bytes(), " a second line\n"));
    _ = try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and a second line\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(2)).bytes(), "and a third"));
    _ = try editor.redo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(2)).bytes(), "\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(3)).bytes(), " a second line\n"));
    editor.deinit();
}

test "editor delete_line and undo/redo" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_2"));
    try expect(editor.buffer.lines.items.len == 3);
    editor.deleteLine(0, .Input);
    try expect(editor.buffer.lines.items.len == 2);
    editor.deleteLine(0, .Input);
    try expect(editor.buffer.lines.items.len == 1);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "and a third"));
    _ = try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).bytes(), "and a second line\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(2)).bytes(), "and a third"));
    try expect(editor.buffer.lines.items.len == 3);
    _ = try editor.redo();
    try expect(editor.buffer.lines.items.len == 1);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).bytes(), "and a third"));
    editor.deinit();
}

test "editor delete_glyph and undo/redo" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_2"));
    try expect(editor.buffer.lines.items.len == 3);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, .Right, .Input);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, .Right, .Input);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, .Right, .Input);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, .Right, .Input);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "o world\n"));
    _ = try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello world\n"));
    try editor.deleteGlyph(Vec2u{ .a = 6, .b = 0 }, .Right, .Input);
    try editor.deleteGlyph(Vec2u{ .a = 6, .b = 0 }, .Right, .Input);
    try editor.deleteGlyph(Vec2u{ .a = 6, .b = 0 }, .Right, .Input);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello ld\n"));
    try editor.deleteGlyph(Vec2u{ .a = 1, .b = 1 }, .Right, .Input);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "ad a second line\n"));
    editor.deleteLine(1, .Input);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "and a third"));
    _ = try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "and a second line\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello world\n"));
    _ = editor.undo() catch |err| {
        try expect(err == EditorError.NothingToUndo);
    };

    _ = try editor.redo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "hello ld\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(1)).*.bytes(), "and a third"));
    editor.deinit();
}

test "editor delete_glyph utf8 and undo/redo" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_3"));
    try expect(editor.buffer.lines.items.len == 1);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, .Right, .Input);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, .Right, .Input);
    try editor.deleteGlyph(Vec2u{ .a = 0, .b = 0 }, .Right, .Input);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "îôûñé👻"));
    _ = try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "🎃àéîôûñé👻"));
    _ = try editor.redo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "îôûñé👻"));
    _ = try editor.undo();
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(0)).*.bytes(), "🎃àéîôûñé👻"));
    editor.deinit();
}

test "editor word_pos_at" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_5"));

    var pos = try editor.wordPosAt(Vec2u{ .a = 16, .b = 3 });
    try expect(pos.a == 14);
    try expect(pos.b == 24);

    pos = try editor.wordPosAt(Vec2u{ .a = 12, .b = 2 });
    try expect(pos.a == 10);
    try expect(pos.b == 13);

    pos = try editor.wordPosAt(Vec2u{ .a = 0, .b = 11 });
    try expect(pos.a == 0);
    try expect(pos.b == 5);

    editor.deinit();
}

test "editor word_pos" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_5"));

    var str = try editor.wordAt(Vec2u{ .a = 16, .b = 3 });
    try expect(std.mem.eql(u8, str, "continuing"));

    str = try editor.wordAt(Vec2u{ .a = 12, .b = 2 });
    try expect(std.mem.eql(u8, str, "one"));

    str = try editor.wordAt(Vec2u{ .a = 0, .b = 11 });
    try expect(std.mem.eql(u8, str, "there"));

    str = try editor.wordAt(Vec2u{ .a = 53, .b = 2 });
    try expect(std.mem.eql(u8, str, "weird"));

    editor.deinit();
}

test "editor delete_chunk" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_5"));
    defer editor.deinit();

    // complete first line, complete second, chunk of the third
    // -----------

    try expect(editor.buffer.linesCount() == 12);
    var cursor = try editor.deleteChunk(Vec2u{ .a = 0, .b = 1 }, Vec2u{ .a = 11, .b = 3 }, .Input);
    try expect(cursor.a == 0);
    try expect(cursor.b == 1);
    try expect(editor.buffer.linesCount() == 10);
    var line = try editor.buffer.getLine(1);
    try expect(std.mem.eql(u8, line.bytes()[0..5], "is co"));
    editor.deinit();

    // chunk within a line
    // ------------

    editor = try Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_5"));
    try expect(editor.buffer.linesCount() == 12);

    // start of a line

    cursor = try editor.deleteChunk(Vec2u{ .a = 0, .b = 3 }, Vec2u{ .a = 6, .b = 3 }, .Input);
    try expect(cursor.a == 0);
    try expect(cursor.b == 3);
    try expect(editor.buffer.linesCount() == 12);
    line = try editor.buffer.getLine(3);
    try expect(std.mem.eql(u8, line.bytes()[0..4], "this"));

    // middle of a line

    cursor = try editor.deleteChunk(Vec2u{ .a = 5, .b = 6 }, Vec2u{ .a = 9, .b = 6 }, .Input);
    try expect(cursor.a == 5);
    try expect(cursor.b == 6);
    try expect(editor.buffer.linesCount() == 12);
    line = try editor.buffer.getLine(6);
    try expect(std.mem.eql(u8, line.bytes()[0..8], "\tOne for"));

    // end of a line

    cursor = try editor.deleteChunk(Vec2u{ .a = 24, .b = 5 }, Vec2u{ .a = 29, .b = 5 }, .Input);
    try expect(cursor.a == 24);
    try expect(cursor.b == 5);
    try expect(editor.buffer.linesCount() == 12);
    line = try editor.buffer.getLine(5);
    try expect(std.mem.eql(u8, line.bytes(), "    Four spaces for this\n"));
}

test "editor paste and undo/redo" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator, try Buffer.initFromFile(allocator, "tests/sample_5"));
    defer editor.deinit();

    var text = try U8Slice.initFromSlice(allocator, "text 👻 copied\nwith return line");
    defer text.deinit();

    try expect(editor.buffer.linesCount() == 12);

    var cursor = try editor.paste(Vec2u{ .a = 0, .b = 9 }, text);
    // it should have added a line
    try expect(editor.buffer.linesCount() == 13);
    // the cursor should have moved to the end of the pasted text
    try expect(cursor.a == 16);
    try expect(cursor.b == 10);
    // lines should look like this
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(9)).*.bytes(), "text 👻 copied\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(10)).*.bytes(), "with return line\n"));
    // let's undo everything
    _ = try editor.undo();
    try expect(editor.buffer.linesCount() == 12);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(9)).*.bytes(), "\n"));
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(10)).*.bytes(), "\n"));

    // in the middle of a line
    var second_text = try U8Slice.initFromSlice(allocator, "👻 text 👻");
    defer second_text.deinit();
    cursor = try editor.paste(Vec2u{ .a = 8, .b = 6 }, second_text);
    try expect(cursor.a == (8 + 8));
    try expect(cursor.b == 6);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(6)).*.bytes(), "\tOne tab👻 text 👻 for this one.\n"));
    _ = try editor.undo();
    try expect(editor.buffer.linesCount() == 12);
    try expect(std.mem.eql(u8, (try editor.buffer.getLine(6)).*.bytes(), "\tOne tab for this one.\n"));
}
