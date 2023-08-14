const std = @import("std");

const Colors = @import("colors.zig");
const U8Slice = @import("u8slice.zig").U8Slice;
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;

pub const LineSyntaxHighlight = struct {
    allocator: std.mem.Allocator,
    columns: std.ArrayList(Vec4u),
    dirty: bool,

    pub fn init(allocator: std.mem.Allocator, dirty: bool) LineSyntaxHighlight {
        return LineSyntaxHighlight{
            .allocator = allocator,
            .columns = std.ArrayList(Vec4u).init(allocator),
            .dirty = dirty,
        };
    }

    pub fn deinit(self: *LineSyntaxHighlight) void {
        self.columns.deinit();
    }

    pub fn getForColumn(self: LineSyntaxHighlight, column: usize) Vec4u {
        if (column >= self.columns.items.len) {
            return Colors.light_gray;
        }
        return self.columns.items[column];
    }
};

// TODO(remy): comment me
pub const SyntaxHighlighter = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(LineSyntaxHighlight),
    word_under_cursor: ?[]const u8,

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn init(allocator: std.mem.Allocator, line_count: usize) !SyntaxHighlighter {
        var lines = std.ArrayList(LineSyntaxHighlight).init(allocator);

        var i: usize = 0;
        while (i < line_count) : (i += 1) {
            try lines.append(LineSyntaxHighlight.init(allocator, true));
        }

        return SyntaxHighlighter{
            .allocator = allocator,
            .lines = lines,
            .word_under_cursor = null,
        };
    }

    pub fn deinit(self: *SyntaxHighlighter) void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit();
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn getLine(self: SyntaxHighlighter, line_number: usize) LineSyntaxHighlight {
        return self.lines.items[line_number];
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn insertNewLine(self: *SyntaxHighlighter, line_position: usize) !void {
        try self.lines.insert(line_position, LineSyntaxHighlight.init(self.allocator, true));
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn removeLine(self: *SyntaxHighlighter, line_position: usize) void {
        var line = self.lines.orderedRemove(line_position);
        line.deinit();
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn setDirty(self: *SyntaxHighlighter, line_range: Vec2u) void {
        var line_pos = line_range.a;
        while (line_pos <= line_range.b) : (line_pos += 1) {
            var line = self.getLine(line_pos);
            line.dirty = true;
            self.lines.items[line_pos] = line;
        }
    }

    pub fn setAllDirty(self: *SyntaxHighlighter) void {
        for (self.lines.items) |*line| {
            line.dirty = true;
        }
    }

    // TODO(remy): comment me
    // TODO(remy): unit test
    pub fn setHighlightWord(self: *SyntaxHighlighter, word: ?[]const u8) bool {
        var has_changed: bool = false;

        // have to highlight a new word
        if (word != null and self.word_under_cursor != null and
            !std.mem.eql(u8, word.?, self.word_under_cursor.?))
        {
            self.setAllDirty();
            has_changed = true;
        }

        // neither we were not highlighting anything or we start
        // not highlighting anything.
        if ((word == null and self.word_under_cursor != null) or (word != null and self.word_under_cursor == null)) {
            self.setAllDirty();
            has_changed = true;
        }

        self.word_under_cursor = word;
        return has_changed;
    }

    // TODO(remy): comment me
    pub fn refresh(self: *SyntaxHighlighter, line_number: usize, line_content: *U8Slice) !bool {
        // if existing and not dirty, nothing to do the highlight is already ok
        var existing = self.lines.items[line_number];
        if (!existing.dirty) {
            return false;
        }

        // refresh this line syntax highlighting
        existing.deinit();

        var line_syntax_highlight = try SyntaxHighlighter.compute(self.allocator, line_content, self.word_under_cursor);
        self.lines.items[line_number] = line_syntax_highlight;
        return true;
    }

    fn reset(self: *SyntaxHighlighter) void {
        self.lines.reset();
    }

    // syntax highlighting
    // -------------------

    fn compute(
        allocator: std.mem.Allocator,
        line_content: *U8Slice,
        word_under_cursor: ?[]const u8,
    ) !LineSyntaxHighlight {
        var columns = std.ArrayList(Vec4u).init(allocator);
        errdefer columns.deinit();

        if (line_content.size() == 0) {
            return LineSyntaxHighlight{
                .allocator = allocator,
                .columns = columns,
                .dirty = false,
            };
        }

        var is_in_quote: usize = 0; // contains which quote char has been used to start
        var is_in_comment: bool = false;
        var char_before_word: usize = 0; // contains which char was before the word
        var current_pos: usize = 0;
        var previous_char: usize = 0;
        var quote_start: usize = 0;
        var word_start: usize = 0;

        var it = try UTF8Iterator.init(line_content.bytes(), 0);
        while (true) {
            var ch: usize = it.glyph()[0];

            // immediately set this glyph color to the default color
            if (is_in_comment) {
                try columns.append(Colors.gray);
            } else {
                try columns.append(Colors.light_gray);
            }

            if (is_in_quote == 0 and previous_char != '\\' and
                (ch == '"' or ch == '\'' or ch == '`'))
            {
                // entering a quoted text
                is_in_quote = ch;
                quote_start = current_pos;
            } else if (is_in_quote == 0 and ((previous_char == '/' and ch == '/') or (previous_char == '#' and ch == ' '))) {
                // entering a comment
                if (columns.items.len > 0) {
                    // TODO(remy): color previous char
                    if (previous_char == '/' and columns.items.len > 1) {
                        columns.items[columns.items.len - 2] = Colors.gray;
                    }
                    columns.items[columns.items.len - 1] = Colors.gray;
                }
                is_in_comment = true;
            } else if (is_in_quote > 0 and ch == is_in_quote and previous_char != '\\') {
                // is in quote and leaving that same quote
                is_in_quote = 0;
                color_with(&columns, quote_start, current_pos + 1, Colors.gray);
            }

            // end of a word
            if (!std.ascii.isAlphanumeric(@as(u8, @intCast(ch))) and ch != '_') {
                if (is_in_quote == 0) {
                    if (std.mem.eql(u8, line_content.bytes()[word_start..it.current_byte], "TODO") or
                        std.mem.eql(u8, line_content.bytes()[word_start..it.current_byte], "XXX") or
                        std.mem.eql(u8, line_content.bytes()[word_start..it.current_byte], "FIXME"))
                    {
                        color_with(&columns, word_start, current_pos, Colors.red);
                    } else if (std.mem.eql(u8, line_content.bytes()[word_start..it.current_byte], "DONE")) {
                        color_with(&columns, word_start, current_pos, Colors.green);
                    } else if (is_in_comment == false and (ch == '(' or ch == '{' or ch == '[' or char_before_word == '.')) {
                        color_with(&columns, word_start, current_pos, Colors.white);
                    }
                }

                // maybe it is the highlighted word?
                if (word_under_cursor != null and
                    std.mem.eql(u8, line_content.bytes()[word_start..it.current_byte], word_under_cursor.?))
                {
                    color_with(&columns, word_start, current_pos, Colors.blue);
                }

                char_before_word = ch;
                word_start = current_pos + 1;
            }

            // move forward and reset every registers
            previous_char = ch;
            current_pos += 1;

            // or stop if there is nothing more
            if (!it.next()) {
                break;
            }
        }

        return LineSyntaxHighlight{
            .allocator = allocator,
            .columns = columns,
            .dirty = false,
        };
    }

    fn color_with(columns: *std.ArrayList(Vec4u), start: usize, end: usize, color: Vec4u) void {
        var idx = start;
        while (idx < end) : (idx += 1) {
            columns.items[idx] = color;
        }
    }

    fn finish_coloring_with(columns: *std.ArrayList(Vec4u), it: *UTF8Iterator, color: Vec4u) !void {
        while (true) {
            try columns.append(color);
            if (!it.next()) {
                break;
            }
        }
    }
};
