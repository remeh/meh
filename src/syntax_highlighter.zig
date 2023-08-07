const std = @import("std");
const c = @import("clib.zig").c;

const Color = @import("colors.zig");
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
            return Color.light_gray;
        }
        return self.columns.items[column];
    }
};

// TODO(remy): comment me
pub const SyntaxHighlighter = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(LineSyntaxHighlight),

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
    
    // TODO(remy): comment me
    pub fn refresh(self: *SyntaxHighlighter, line_number: usize, line_content: *U8Slice) !bool {
        // if existing and not dirty, nothing to do the highlight is already ok
        var existing = self.lines.items[line_number];
        if (!existing.dirty) {
            return false;
        }

        existing.deinit();

        var line_syntax_highlight = try SyntaxHighlighter.compute(self.allocator, line_content);
        self.lines.items[line_number] = line_syntax_highlight;
        return true;
    }

    fn reset(self: *SyntaxHighlighter) void {
        self.lines.reset();
    }
    
    fn compute(allocator: std.mem.Allocator, line_content: *U8Slice) !LineSyntaxHighlight {
        // TODO(remy): actual computation of the syntax highlighting.
        
        var columns = std.ArrayList(Vec4u).init(allocator);
        errdefer columns.deinit();

        if (std.mem.containsAtLeast(u8, line_content.bytes(), 1, "//")) {
            var it = try UTF8Iterator.init(line_content.bytes(), 0);
            while (true) {
                columns.append(Color.gray) catch {};

                if (!it.next()) {
                    break;
                }
            }
        }
        
        return LineSyntaxHighlight{
            .allocator = allocator,
            .columns = columns,
            .dirty = false,
        };
    }
};
