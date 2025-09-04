const std = @import("std");

const Buffer = @import("buffer.zig").Buffer;
const Colors = @import("colors.zig");
const U8Slice = @import("u8slice.zig").U8Slice;
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;

const keywords = [_][]const u8{
    "type",
    "interface",
    "struct",
    "const",

    "defer",
    "errdefer",

    "function",
    "func",
    "fn",

    "break",
    "else",
    "try",
    "while",
    "for",
    "return",
    "if",
    "catch",

    "var",
    "let",
    "pub",
    "std",

    "true",
    "false",
    "zig",
    "import",
};

pub const LineSyntaxHighlight = struct {
    allocator: std.mem.Allocator,
    columns: std.ArrayList(Vec4u),
    // highlight_rects is the glyph position (start, end) to highlight
    // using a rect.
    highlight_rects: std.ArrayList(Vec2u),
    dirty: bool,

    pub fn init(allocator: std.mem.Allocator, dirty: bool) LineSyntaxHighlight {
        return LineSyntaxHighlight{
            .allocator = allocator,
            .columns = std.ArrayList(Vec4u).init(allocator),
            .highlight_rects = std.ArrayList(Vec2u).init(allocator),
            .dirty = dirty,
        };
    }

    pub fn deinit(self: *LineSyntaxHighlight) void {
        self.columns.deinit();
        self.highlight_rects.deinit();
    }

    pub fn getForColumn(self: LineSyntaxHighlight, column: usize) Vec4u {
        if (column >= self.columns.items.len) {
            return Colors.light_gray;
        }
        return self.columns.items[column];
    }

    pub fn copy(self: *LineSyntaxHighlight, allocator: std.mem.Allocator) !LineSyntaxHighlight {
        var columns = std.ArrayList(Vec4u).init(allocator);
        try columns.appendSlice(self.columns.items);
        var rects = std.ArrayList(Vec2u).init(allocator);
        try rects.appendSlice(self.highlight_rects.items);
        return LineSyntaxHighlight{
            .allocator = allocator,
            .columns = columns,
            .highlight_rects = rects,
            .dirty = false,
        };
    }
};

/// SyntaxHighlighter is a token-based line syntax highlighter.
pub const SyntaxHighlighter = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(LineSyntaxHighlight),
    keyword_matcher: std.StringHashMap(void),
    word_under_cursor: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, line_count: usize) !SyntaxHighlighter {
        var lines = std.ArrayList(LineSyntaxHighlight).init(allocator);

        var i: usize = 0;
        while (i < line_count) : (i += 1) {
            try lines.append(LineSyntaxHighlight.init(allocator, true));
        }

        var keyword_matcher = std.StringHashMap(void).init(allocator);
        for (keywords) |keyword| {
            try keyword_matcher.put(keyword, {});
        }

        return SyntaxHighlighter{
            .allocator = allocator,
            .lines = lines,
            .word_under_cursor = null,
            .keyword_matcher = keyword_matcher,
        };
    }

    pub fn deinit(self: *SyntaxHighlighter) void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit();
        self.keyword_matcher.deinit();
    }

    pub fn getLine(self: SyntaxHighlighter, line_number: usize) LineSyntaxHighlight {
        return self.lines.items[line_number];
    }

    pub fn insertNewLine(self: *SyntaxHighlighter, line_position: usize) !void {
        try self.lines.insert(line_position, LineSyntaxHighlight.init(self.allocator, true));
    }

    // removeLine removes highlighting information on the given line.
    pub fn removeLine(self: *SyntaxHighlighter, line_position: usize) void {
        var line = self.lines.orderedRemove(line_position);
        line.deinit();
    }

    /// setDirty sets a range of syntax lines to dirty.
    pub fn setDirty(self: *SyntaxHighlighter, line_range: Vec2u) void {
        var line_pos = line_range.a;
        while (line_pos <= line_range.b) : (line_pos += 1) {
            if (line_pos >= self.lines.items.len) {
                break;
            }
            self.lines.items[line_pos].dirty = true;
        }
    }

    /// setAllDirty sets all syntax lines to dirty.
    pub fn setAllDirty(self: *SyntaxHighlighter) void {
        for (self.lines.items) |*line| {
            line.dirty = true;
        }
    }

    /// setHighlightWord sets what word to highlight with the syntax highlighter.
    /// Returns whether or not the highlighting has change.
    pub fn setHighlightWord(self: *SyntaxHighlighter, word: ?[]const u8) bool {
        var has_changed: bool = false;

        // have to highlight a new word
        if (word != null and self.word_under_cursor != null and
            !std.mem.eql(u8, word.?, self.word_under_cursor.?))
        {
            self.setAllDirty();
            has_changed = true;
        }

        // eiither we were not highlighting anything or we start
        // not highlighting anything.
        if ((word == null and self.word_under_cursor != null) or (word != null and self.word_under_cursor == null)) {
            self.setAllDirty();
            has_changed = true;
        }

        self.word_under_cursor = word;
        return has_changed;
    }

    /// refresh re-compute the syntax highlighting for the given line.
    pub fn refresh(self: *SyntaxHighlighter, line_number: usize, line_content: *U8Slice) !bool {
        if (self.lines.items.len == 0) {
            return false;
        }

        // if existing and not dirty, nothing to do the highlight is already ok
        var existing = self.lines.items[line_number];
        if (!existing.dirty) {
            return false;
        }

        // refresh this line syntax highlighting
        existing.deinit();

        const line_syntax_highlight = try SyntaxHighlighter.compute(self.allocator, line_content, self.word_under_cursor, self.keyword_matcher);
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
        keyword_matcher: std.StringHashMap(void),
    ) !LineSyntaxHighlight {
        var columns = std.ArrayList(Vec4u).init(allocator);
        errdefer columns.deinit();
        var highlight_rects = std.ArrayList(Vec2u).init(allocator);
        errdefer highlight_rects.deinit();

        if (line_content.size() == 0) {
            return LineSyntaxHighlight{
                .allocator = allocator,
                .columns = columns,
                .dirty = false,
                .highlight_rects = highlight_rects,
            };
        }

        var is_in_quote: usize = 0; // contains which quote char has been used to start
        var is_in_comment: bool = false;
        var char_before_word: usize = 0; // contains which char was before the word
        var current_pos: usize = 0;
        var previous_char: usize = 0;
        var quote_start: usize = 0;
        var word_start: usize = 0;
        var tabs_encountered: usize = 0; // how many tabs we've been through already

        var it = try UTF8Iterator.init(line_content.bytes(), 0);
        while (true) {
            const ch: usize = it.glyph()[0];

            // immediately set this glyph color to the default color
            if (is_in_comment) {
                try columns.append(Colors.gray);
            } else {
                try columns.append(Colors.light_gray);
            }

            if (ch == '\t') {
                tabs_encountered += 1;
            }

            if (is_in_quote == 0 and previous_char != '\\' and
                (ch == '"' or ch == '\'' or ch == '`'))
            {
                // entering a quoted text
                is_in_quote = ch;
                quote_start = current_pos;
            } else if (is_in_quote == 0 and ((previous_char == '/' and ch == '/') or (previous_char == '#' and ch == ' ') or (previous_char == '#' and ch == '#') or (previous_char == '#' and ch == '\n'))) {
                // entering a comment
                if (columns.items.len > 0) {
                    // TODO(remy): color previous char
                    if ((previous_char == '/' or previous_char == '#') and columns.items.len > 1) {
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
                    const str = line_content.bytes()[word_start..it.current_byte];

                    if (std.mem.eql(u8, str, "TODO") or
                        std.mem.eql(u8, str, "XXX") or
                        std.mem.eql(u8, str, "FIXME"))
                    {
                        color_with(&columns, word_start, current_pos, Colors.red);
                    } else if (std.mem.eql(u8, str, "DONE")) {
                        color_with(&columns, word_start, current_pos, Colors.green);
                    } else if (is_in_comment == false and (ch == '(' or ch == '{' or ch == '[' or char_before_word == '.')) {
                        color_with(&columns, word_start, current_pos, Colors.white);
                    }

                    if (!is_in_comment and str.len > 0 and keyword_matcher.contains(str)) {
                        color_with(&columns, word_start, current_pos, Colors.gray_blue);
                    }
                }

                // maybe it is the highlighted word?
                if (word_under_cursor != null and
                    std.mem.eql(u8, line_content.bytes()[word_start..it.current_byte], word_under_cursor.?))
                {
                    // *3 since since we already move of 1 because of the \t itself
                    const tabs_offset: usize = tabs_encountered * 3;
                    // create a rect for this word
                    try highlight_rects.append(Vec2u{
                        .a = word_start + tabs_offset,
                        .b = current_pos + tabs_offset,
                    });
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
            .highlight_rects = highlight_rects,
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

test "line_syntax_highlighter main test" {
    const allocator = std.testing.allocator;

    var buffer = try Buffer.initFromFile(allocator, "tests/sample_6.zig");
    defer buffer.deinit();
    try std.testing.expectEqual(buffer.lines.items.len, 5);

    var sh = try SyntaxHighlighter.init(allocator, buffer.lines.items.len);
    defer sh.deinit();

    var i: usize = 0;
    for (buffer.lines.items) |*line| {
        _ = try sh.refresh(i, line);
        i += 1;
    }

    try std.testing.expectEqual(sh.lines.items[0].dirty, false);
    try std.testing.expectEqual(sh.lines.items[1].dirty, false);
    try std.testing.expectEqual(sh.lines.items[2].dirty, false);
    try std.testing.expectEqual(sh.lines.items[3].dirty, false);
    try std.testing.expectEqual(sh.lines.items[4].dirty, false);

    sh.setAllDirty();

    try std.testing.expectEqual(sh.lines.items[0].dirty, true);
    try std.testing.expectEqual(sh.lines.items[1].dirty, true);
    try std.testing.expectEqual(sh.lines.items[2].dirty, true);
    try std.testing.expectEqual(sh.lines.items[3].dirty, true);
    try std.testing.expectEqual(sh.lines.items[4].dirty, true);

    i = 0;
    for (buffer.lines.items) |*line| {
        _ = try sh.refresh(i, line);
        i += 1;
    }

    try std.testing.expectEqual(true, sh.setHighlightWord("log"));
    try std.testing.expectEqual(true, try sh.refresh(3, &buffer.lines.items[3]));

    const line3 = sh.getLine(3);
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(0)); // space
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(1)); // space
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(2)); // space
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(3)); // space
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(4)); // s
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(5)); // t
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(6)); // d
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(7)); // .
    try std.testing.expectEqual(Colors.blue, line3.getForColumn(8)); // l
    try std.testing.expectEqual(Colors.blue, line3.getForColumn(9)); // o
    try std.testing.expectEqual(Colors.blue, line3.getForColumn(10)); // g
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(11)); // .
    try std.testing.expectEqual(Colors.white, line3.getForColumn(12)); // d
    try std.testing.expectEqual(Colors.white, line3.getForColumn(13)); // e
    try std.testing.expectEqual(Colors.white, line3.getForColumn(14)); // b
    try std.testing.expectEqual(Colors.white, line3.getForColumn(15)); // u
    try std.testing.expectEqual(Colors.white, line3.getForColumn(16)); // g
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(17)); // (
    try std.testing.expectEqual(Colors.gray, line3.getForColumn(18)); // "
    try std.testing.expectEqual(Colors.gray, line3.getForColumn(19)); // h
    try std.testing.expectEqual(Colors.gray, line3.getForColumn(20)); // e
    try std.testing.expectEqual(Colors.gray, line3.getForColumn(21)); // l
    try std.testing.expectEqual(Colors.gray, line3.getForColumn(22)); // l
    try std.testing.expectEqual(Colors.gray, line3.getForColumn(23)); // o
    try std.testing.expectEqual(Colors.gray, line3.getForColumn(24)); // "
    try std.testing.expectEqual(Colors.light_gray, line3.getForColumn(25)); // ,

    sh.removeLine(4);
    try std.testing.expectEqual(sh.lines.items.len, 4);
    sh.removeLine(1);
    try std.testing.expectEqual(sh.lines.items.len, 3);
}
