const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const Buffer = @import("buffer.zig").Buffer;
const Editor = @import("editor.zig").Editor;
const ImVec2 = @import("vec.zig").ImVec2;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;

// TODO(remy): where should we define this?
// TODO(remy): comment
pub const border_offset = 5;

pub const InputMode = enum {
    Insert,
    Replace,
    Visual,
    VLine,
};

// TODO(remy): comment
pub const Cursor = struct {
    pos: Vec2i,

    // Constructors
    // ------------

    pub fn init() Cursor {
        return Cursor{
            .pos = Vec2i{ .a = 0, .b = 0 },
        };
    }

    // Methods
    // -------

    // TODO(remy): we probably miss the font size here
    // TODO(remy): consider redrawing the character which is under the cursor in a reverse color to see it above the cursor
    pub fn render(self: Cursor, draw_list: *c.ImDrawList, input_mode: InputMode, line_offset: i64, font_size: Vec2f) void {
        switch (input_mode) {
            .Insert => {
                var x1 = @intToFloat(f32, self.pos.a) * font_size.a;
                var x2 = x1 + 2;
                var y1 = @intToFloat(f32, self.pos.b - line_offset) * font_size.b;
                var y2 = @intToFloat(f32, self.pos.b + 1 - line_offset) * (font_size.b);
                c.ImDrawList_AddRectFilled(
                    draw_list,
                    ImVec2(border_offset + x1, border_offset + y1),
                    ImVec2(border_offset + x2, border_offset + y2),
                    0xFFFFFFFF,
                    1.0,
                    0,
                );
            },
            else => {
                var x1 = @intToFloat(f32, self.pos.a) * font_size.a;
                var x2 = @intToFloat(f32, self.pos.a + 1) * font_size.a;
                var y1 = @intToFloat(f32, self.pos.b - line_offset) * font_size.b;
                var y2 = @intToFloat(f32, self.pos.b + 1 - line_offset) * (font_size.b);
                c.ImDrawList_AddRectFilled(
                    draw_list,
                    ImVec2(border_offset + x1, border_offset + y1),
                    ImVec2(border_offset + x2, border_offset + y2),
                    0xFFFFFFFF,
                    1.0,
                    0,
                );
            },
        }
    }
};

// TODO(remy): comment
pub const WidgetText = struct {
    allocator: std.mem.Allocator,
    app: *App,
    cursor: Cursor, // TODO(remy): replace me with a custom (containing cursor mode)
    editor: Editor,
    input_mode: InputMode,
    visible_lines: Vec2i,

    // Constructors
    // ------------

    // TODO(remy): comment
    pub fn initEmpty(allocator: std.mem.Allocator, app: *App) WidgetText {
        var buffer = Buffer.initEmpty(allocator);
        return WidgetText{
            .allocator = allocator,
            .app = app,
            .editor = Editor.init(allocator, buffer),
            .visible_lines = undefined,
            .cursor = Cursor.init(),
            .input_mode = InputMode.Insert,
        };
    }

    // TODO(remy): comment
    pub fn initWithBuffer(allocator: std.mem.Allocator, app: *App, buffer: Buffer) WidgetText {
        return WidgetText{
            .allocator = allocator,
            .app = app,
            .editor = Editor.init(allocator, buffer),
            .visible_lines = Vec2i{ .a = 0, .b = 50 },
            .cursor = Cursor.init(),
            .input_mode = InputMode.Insert,
        };
    }

    pub fn deinit(self: *WidgetText) void {
        self.editor.deinit();
    }

    // Rendering methods
    // -----------------

    // pub fn set_window_size() // TODO(remy): implement me and unit test

    // TODO(remy): comment
    // TODO(remy): unit test (at least to validate that there is no leaks)
    pub fn render(self: WidgetText) void {
        var draw_list = c.igGetWindowDrawList();

        var one_char_size = ImVec2(0, 0);
        c.igCalcTextSize(&one_char_size, "0", null, false, 0.0);

        self.renderLines(draw_list, one_char_size);
        self.renderCursor(draw_list, one_char_size);
    }

    fn renderCursor(self: WidgetText, draw_list: *c.ImDrawList, one_char_size: c.ImVec2) void {
        self.cursor.render(draw_list, self.input_mode, self.visible_lines.a, Vec2f{ .a = one_char_size.x, .b = one_char_size.y });
    }

    fn renderLines(self: WidgetText, draw_list: *c.ImDrawList, one_char_size: c.ImVec2) void {
        var i: usize = @intCast(usize, self.visible_lines.a);
        var y_offset: f32 = 0.0;

        while (i < self.visible_lines.b) : (i += 1) {
            if (self.editor.buffer.getLine(i)) |line| {
                var buff: []u8 = line.data.items;

                // empty line
                if (buff.len == 0 or (buff.len == 1 and buff[0] == '\n')) {
                    c.ImDrawList_AddText_Vec2(draw_list, ImVec2(border_offset, border_offset + y_offset), 0xFFFFFFFF, "", 0);
                    y_offset += one_char_size.y;
                    continue;
                }

                buff[buff.len - 1] = 0; // finish the buffer with a 0 for the C-land
                c.ImDrawList_AddText_Vec2(draw_list, ImVec2(border_offset, border_offset + y_offset), 0xFFFFFFFF, @ptrCast([*:0]const u8, buff), 0);
                y_offset += one_char_size.y;

                // std.log.debug("self.buffer.data.items[{d}..{d}] (len: {d}) data: {s}", .{ @intCast(usize, pos.a), @intCast(usize, pos.b), self.buffer.data.items.len, @ptrCast([*:0]const u8, buff) });
            } else |_| {
                // TODO(remy): do something with the error
            }
        }
    }

    // Events methods
    // --------------

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn onTextInput(self: *WidgetText, ch: u8) bool {
        switch (ch) {
            'q' => self.app.is_running = false,
            'n' => self.newLine(),
            'h' => self.moveCursor(Vec2i{ .a = -1, .b = 0 }),
            'j' => self.moveCursor(Vec2i{ .a = 0, .b = 1 }),
            'k' => self.moveCursor(Vec2i{ .a = 0, .b = -1 }),
            'l' => self.moveCursor(Vec2i{ .a = 1, .b = 0 }),
            'd' => self.editor.deleteLine(@intCast(usize, self.cursor.pos.b)),
            'x' => self.editor.deleteChar(self.cursor.pos, false) catch {},
            'u' => self.undo(),
            'i' => self.input_mode = .Insert, // TODO(remy): finish
            'r' => self.input_mode = .Replace, // TODO(remy): finish
            else => return false,
        }
        return true;
    }

    // Text edition methods
    // -------------------

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn moveCursor(self: *WidgetText, move: Vec2i) void {
        // x movement
        if (self.cursor.pos.a + move.a <= 0) {
            self.cursor.pos.a = 0;
        } else if (self.cursor.pos.a + move.a >= self.editor.buffer.lines.items[@intCast(usize, self.cursor.pos.b)].size()) {
            self.cursor.pos.a = @intCast(i64, self.editor.buffer.lines.items[@intCast(usize, self.cursor.pos.b)].size()) - 1;
        } else {
            self.cursor.pos.a += move.a;
        }
        // y movement
        if (self.cursor.pos.b + move.b <= 0) {
            self.cursor.pos.b = 0;
        } else if (self.cursor.pos.b + move.b >= @intCast(usize, self.editor.buffer.lines.items.len) - 1) {
            self.cursor.pos.b = @intCast(i64, self.editor.buffer.lines.items.len) - 1;
        } else {
            self.cursor.pos.b += move.b;
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit tes
    pub fn newLine(self: *WidgetText) void {
        self.editor.newLine(self.cursor.pos, true);
        // TODO(remy): smarter positioning of the cursor
        self.cursor.pos.a = 0;
        self.cursor.pos.b += 1;
    }

    // TODO(remy): comment
    pub fn undo(self: *WidgetText) void {
        self.editor.undo() catch |err| {
            std.log.err("WidgetText.undo: can't undo: {}", .{err});
        };
    }
};

test "editor moveCursor" {
    const allocator = std.testing.allocator;
    var app: *App = undefined;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var editor = WidgetText.initWithBuffer(allocator, app, buffer);
    editor.cursor.pos = Vec2i{ .a = 0, .b = 0 };

    // top of the file, moving up shouldn't do anything
    editor.moveCursor(Vec2i{ .a = 0, .b = -1 });
    try expect(editor.cursor.pos.a == 0);
    try expect(editor.cursor.pos.b == 0);
    // move down
    editor.moveCursor(Vec2i{ .a = 0, .b = 1 });
    try expect(editor.cursor.pos.a == 0);
    try expect(editor.cursor.pos.b == 1);
    // big move down, should reach the last line of the file
    editor.moveCursor(Vec2i{ .a = 0, .b = 15 });
    try expect(editor.cursor.pos.a == 0);
    try expect(editor.cursor.pos.b == buffer.lines.items.len - 1);
    // big move up, should reach the top line
    editor.moveCursor(Vec2i{ .a = 0, .b = -15 });
    try expect(editor.cursor.pos.a == 0);
    try expect(editor.cursor.pos.b == 0);
    // move right
    editor.moveCursor(Vec2i{ .a = 1, .b = 0 });
    try expect(editor.cursor.pos.a == 1);
    try expect(editor.cursor.pos.b == 0);
    // big move right, should reach the end of the line
    editor.moveCursor(Vec2i{ .a = 100, .b = 0 });
    try expect(editor.cursor.pos.a == buffer.lines.items[0].size() - 1);
    try expect(editor.cursor.pos.b == 0);
    // move left
    editor.moveCursor(Vec2i{ .a = -1, .b = 0 });
    try expect(editor.cursor.pos.a == buffer.lines.items[0].size() - 2);
    try expect(editor.cursor.pos.b == 0);
    // big move left, should reach the start of the line
    editor.moveCursor(Vec2i{ .a = -100, .b = 0 });
    try expect(editor.cursor.pos.a == 0);
    try expect(editor.cursor.pos.b == 0);
    // big move right and up, should reach the last line and its end
    editor.moveCursor(Vec2i{ .a = 100, .b = 100 });
    try expect(editor.cursor.pos.a == buffer.lines.items[0].size() - 1);
    try expect(editor.cursor.pos.b == buffer.lines.items.len - 1);

    editor.deinit();
}

// TODO(remy): unit test
test "editor_init_deinit" {
    const allocator = std.testing.allocator;
    var app: *App = undefined;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    var editor = WidgetText.initWithBuffer(allocator, app, buffer);
    editor.deinit();
}
