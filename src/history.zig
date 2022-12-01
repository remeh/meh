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
};

// TODO(remy): comment
pub const History = struct {
    // TODO(remy): comment
    pub fn undo(editor: *Editor, change: Change) !void {
        switch (change.type) {
            .InsertNewLine => {
                var extra = try editor.buffer.getLine(@intCast(u64, change.pos.b + 1));
                var line = try editor.buffer.getLine(@intCast(u64, change.pos.b));
                // remove the \n
                line.data.shrinkAndFree(line.size() - 1);
                // append the rest of data
                try line.data.appendSlice(extra.bytes());
                // remove the next line which has been appended already
                var data = editor.buffer.lines.orderedRemove(change.pos.b + 1); // XXX(remy): are we sure with this +1?
                data.deinit();
            },
            .InsertUtf8Char => {
                // size of the utf8 char
                var line = try editor.buffer.getLine(change.pos.b);
                var char_pos = change.pos.a;
                var utf8_size = try std.unicode.utf8ByteSequenceLength(line.data.items[char_pos]);
                while (utf8_size > 0) : (utf8_size -= 1) {
                    _ = line.data.orderedRemove(char_pos);
                }
            },
            .DeleteUtf8Char => {
                var line = try editor.buffer.getLine(@intCast(u64, change.pos.b));
                try line.data.insertSlice(change.pos.a, change.data.bytes());
                change.data.deinit();
            },
            .DeleteLine => {
                try editor.buffer.lines.insert(change.pos.b, change.data);
            },
        }
    }
};
