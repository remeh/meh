const std = @import("std");

const Editor = @import("editor.zig").Editor;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;

/// ChangeType are the different changes that can be applied on the text.
/// The type is then used during undo/redo to know what has to be reverted
/// or re-applied.
pub const ChangeType = enum {
    /// `DeleteGlyph` is the action of having removed a character in a line.
    /// The vector `pos` contains the position of the removed character
    /// before it was removed. This pos is in utf8.
    /// Deleted utf8 is available in `data`.
    DeleteGlyph,
    /// `InsertUtf8Text` is the action of inserting an utf8 character in a line.
    /// The vector `pos` contains the position of the inserted character
    /// the position it is inserted. This pos is in utf8.
    /// There is no data in `data`.
    InsertUtf8Text,
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

    /// redo re-applies a change that has been previously reverted.
    pub fn redo(self: *Change, editor: *Editor) !void {
        switch (self.type) {
            .InsertNewLine => {
                try editor.newLine(self.pos, .Redo);
            },
            .DeleteLine => {
                editor.deleteLine(self.pos.b, .Redo);
            },
            .InsertUtf8Text => {
                try editor.insertUtf8Text(self.pos, self.data.bytes(), .Redo);
            },
            .DeleteGlyph => {
                try editor.deleteGlyph(self.pos, .Right, .Redo);
            },
        }
    }

    /// undo reverts a change having been done on the current editor.
    pub fn undo(self: *Change, editor: *Editor) !void {
        switch (self.type) {
            .InsertNewLine => {
                var extra = try editor.buffer.getLine(@intCast(u64, self.pos.b + 1));
                if (extra.size() > 1) {
                    // append the extra text but don't keep the \n
                    try editor.insertUtf8Text(self.pos, extra.bytes()[0 .. extra.size() - 1], .Undo);
                }
                editor.deleteLine(self.pos.b + 1, .Undo);
            },
            .InsertUtf8Text => {
                var end = self.pos;
                end.a += self.data.size();
                _ = try editor.deleteChunk(self.pos, end, .Undo);
            },
            .DeleteGlyph => {
                try editor.insertUtf8Text(self.pos, self.data.bytes(), .Undo);
            },
            .DeleteLine => {
                try editor.buffer.lines.insert(self.pos.b, self.data);
                try editor.syntax_highlighter.insertNewLine(self.pos.b);
                // we re-inserted the line into the document, it is not owned
                // by this change anymore.
                self.data = U8Slice.initEmpty(editor.allocator);
            },
        }
    }
};
