const std = @import("std");
const c = @import("clib.zig").c;

const Buffer = @import("buffer.zig").Buffer;
const ImVec2 = @import("vec.zig").ImVec2;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;

// TODO(remy): where should we define this?
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
    pub fn render(self: Cursor, draw_list: *c.ImDrawList, input_mode: InputMode, line_offset: i64, font_size: Vec2f) void {
        switch (input_mode) {
            .Insert => {
                var x1 = @intToFloat(f32, self.pos.a) * font_size.a;
                var x2 = x1 + 2;
                var y1 = @intToFloat(f32, self.pos.b - line_offset) * font_size.b;
                var y2 = @intToFloat(f32, self.pos.b + 1 - line_offset) * (font_size.b) - 2;
                c.ImDrawList_AddRectFilled(
                    draw_list,
                    ImVec2(border_offset + x1, border_offset + y1),
                    ImVec2(border_offset + x2, border_offset + y2),
                    0xFFFFFFFF,
                    0.4,
                    0,
                );
            },
            else => {
                var x1 = @intToFloat(f32, self.pos.a) * font_size.a;
                var x2 = @intToFloat(f32, self.pos.a + 1) * font_size.a;
                var y1 = @intToFloat(f32, self.pos.b - line_offset) * font_size.b;
                var y2 = @intToFloat(f32, self.pos.b + 1 - line_offset) * (font_size.b) - 2;
                c.ImDrawList_AddRectFilled(
                    draw_list,
                    ImVec2(border_offset + x1, border_offset + y1),
                    ImVec2(border_offset + x2, border_offset + y2),
                    0xFFFFFFFF,
                    0.4,
                    0,
                );
            },
        }
    }
};

// TODO(remy): comment
pub const Editor = struct {
    allocator: std.mem.Allocator,
    buffer: Buffer,
    visible_lines: Vec2i,
    input_mode: InputMode,
    cursor: Cursor, // TODO(remy): replace me with a custom (containing cursor mode)

    // Constructors
    // ------------

    // TODO(remy): comment
    pub fn initEmpty(allocator: std.mem.Allocator) Editor {
        return Editor{
            .allocator = allocator,
            .buffer = Buffer.initEmpty(allocator),
            .visible_lines = undefined,
            .cursor = Cursor.init(),
            .input_mode = InputMode.Insert,
        };
    }

    // TODO(remy): comment
    pub fn initWithBuffer(allocator: std.mem.Allocator, buffer: Buffer) Editor {
        return Editor{
            .allocator = allocator,
            .buffer = buffer,
            .visible_lines = Vec2i{ .a = 0, .b = 50 },
            .cursor = Cursor.init(),
            .input_mode = InputMode.Insert,
        };
    }

    pub fn deinit(self: *Editor) void {
        self.buffer.deinit();
    }

    // Methods
    // -------

    // pub fn set_window_size() // TODO(remy): implement me and unit test

    // TODO(remy): comment
    // TODO(remy): unit test (at least to validate that there is no leaks)
    pub fn render(self: Editor) void {
        var draw_list = c.igGetWindowDrawList();

        self.renderLines(draw_list);
        self.renderCursor(draw_list);
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn moveCursor(self: *Editor, move: Vec2i) void {
        // TODO(remy): test for position,
        self.cursor.pos.a += move.a;
        self.cursor.pos.b += move.b;
    }

    fn renderCursor(self: Editor, draw_list: *c.ImDrawList) void {
        self.cursor.render(draw_list, self.input_mode, self.visible_lines.a, Vec2f{ .a = 7, .b = 17 });
    }

    fn renderLines(self: Editor, draw_list: *c.ImDrawList) void {
        var i: usize = @intCast(usize, self.visible_lines.a);
        var y_offset: f32 = 0.0;
        while (i < self.visible_lines.b) : (i += 1) {
            if (self.buffer.getLinePos(i)) |pos| {
                var buff: []u8 = self.buffer.data.items[@intCast(usize, pos.a) .. @intCast(usize, pos.b) + 1];

                // empty line
                if (buff.len == 0 or (buff.len == 1 and buff[0] == '\n')) {
                    c.ImDrawList_AddText_Vec2(draw_list, ImVec2(5, 5 + y_offset), 0xFFFFFFFF, "", 0);
                    y_offset += 17.0;
                    continue;
                }

                buff[buff.len - 1] = 0; // finish the buffer with a 0 for the C-land
                c.ImDrawList_AddText_Vec2(draw_list, ImVec2(5, 5 + y_offset), 0xFFFFFFFF, @ptrCast([*:0]const u8, buff), 0);
                y_offset += 17.0;

                // std.log.debug("self.buffer.data.items[{d}..{d}] (len: {d}) data: {s}", .{ @intCast(usize, pos.a), @intCast(usize, pos.b), self.buffer.data.items.len, @ptrCast([*:0]const u8, buff) });
            } else |_| {
                // TODO(remy): do something with the error
            }
        }
    }
};

// TODO(remy): unit test
test "editor_init_deinit" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    var editor = Editor.initWithBuffer(allocator, buffer);
    editor.deinit();
}
