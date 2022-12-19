const std = @import("std");

const Editor = @import("editor.zig").Editor;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;

// TODO(remy): comment
pub const ChangeType = enum {
    /// `DeleteUtf8Char` is the action of having removed a character in a line.
    /// The vector `pos` contains the position of the removed character
    /// before it was removed. This pos is in utf8.
    /// Deleted utf8 is available in `data`.
    DeleteUtf8Char,
    /// `InsertUtf8Char` is the action of inserting an utf8 character in a line.
    /// The vector `pos` contains the position of the inserted character
    /// the position it is inserted. This pos is in utf8.
    /// There is no data in `data`.
    InsertUtf8Char,
    /// `DeleteLine` is the action of a completely deleted line.
    /// The vector `pos` contains the line at which it was before deletion.
    /// Deleted line is available in `data`.
    DeleteLine,
    /// `InsertNewLine` is the action of creating a new line by inserting a newline char.
    /// The vector `pos` contains the character position where the newline char has been inserted.
    /// There is no data in `data`.
    InsertNewLine,
};

/// Change represents a modification of a buffer.
/// The Change owns the `data` and has to release it.
/// The `pos` vector can have different meanings depending on the `type` of the Change.
pub const Change = struct {
    /// block_id is used to creates blocks of edit, in order to revert a complete block
    /// in a row.
    block_id: i64,
    type: ChangeType,
    data: U8Slice,
    /// depending on the `change_type`, only the first field of the
    /// vector could be used (for instance for a line action).
    pos: Vec2u,

    pub fn deinit(self: *Change) void {
        self.data.deinit();
    }

    // TODO(remy): comment
    pub fn redo(self: *Change, editor: *Editor) !void {
        switch (self.type) {
            .InsertNewLine => {
                try editor.newLine(self.pos, .Redo);
            },
            .DeleteLine => {
                editor.deleteLine(self.pos.b, .Redo);
            },
            .InsertUtf8Char => {
                try editor.insertUtf8Text(self.pos, self.data.bytes(), .Redo);
            },
            .DeleteUtf8Char => {
                try editor.deleteGlyph(self.pos, .Right, .Redo);
            },
        }
    }

    // TODO(remy): comment
    pub fn undo(self: *Change, editor: *Editor) !void {
        switch (self.type) {
            .InsertNewLine => {
                var extra = try editor.buffer.getLine(@intCast(u64, self.pos.b + 1));
                var line = try editor.buffer.getLine(@intCast(u64, self.pos.b));
                // remove the \n
                line.data.shrinkAndFree(line.size() - 1);
                // append the rest of data
                try line.data.appendSlice(extra.bytes());
                // remove the next line which has been appended already
                var data = editor.buffer.lines.orderedRemove(self.pos.b + 1); // XXX(remy): are we sure with this +1?
                data.deinit();
            },
            .InsertUtf8Char => {
                var line = try editor.buffer.getLine(self.pos.b);
                var i: usize = 0;
                while (i < self.data.size()) : (i += 1) {
                    _ = line.data.orderedRemove(self.pos.a);
                }
            },
            .DeleteUtf8Char => {
                var line = try editor.buffer.getLine(@intCast(u64, self.pos.b));
                try line.data.insertSlice(self.pos.a, self.data.bytes());
            },
            .DeleteLine => {
                try editor.buffer.lines.insert(self.pos.b, self.data);
                // we re-inserted the line into the document, it is not owned
                // by this change anymore.
                self.data = U8Slice.initEmpty(editor.allocator);
            },
        }
    }
};
