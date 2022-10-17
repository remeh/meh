const std = @import("std");

const Buffer = @import("../buffer.zig").Buffer;
const c = @import("../clib.zig").c;
const Vec2i = @import("../vec.zig").Vec2i;
const ImVec2 = @import("../vec.zig").ImVec2;

// TODO(remy): comment me
pub const Line = struct {};

// TODO(remy): comment me
// TODO(remy): font size
pub const Editor = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(Line),
    buffer: Buffer,
    visible_lines: Vec2i,
    cursor_pos: Vec2i, // TODO(remy): replace me with a custom (containing cursor mode)

    // Constructors
    // ------------

    // TODO(remy): comment me
    pub fn initEmpty(allocator: std.mem.Allocator) Editor {
        return Editor{
            .allocator = allocator,
            .lines = std.ArrayList(Line).init(allocator),
            .buffer = Buffer.initEmpty(allocator),
            .visible_lines = undefined,
            .cursor_pos = Vec2i{ .a = 1, .b = 5 },
        };
    }

    // TODO(remy): comment me
    pub fn initWithBuffer(allocator: std.mem.Allocator, buffer: Buffer) Editor {
        return Editor{
            .allocator = allocator,
            .lines = std.ArrayList(Line).init(allocator),
            .buffer = buffer,
            .visible_lines = Vec2i{ .a = 0, .b = 50 },
            .cursor_pos = Vec2i{ .a = 1, .b = 5 },
        };
    }

    pub fn deinit(self: *Editor) void {
        self.lines.deinit();
        self.buffer.deinit();
    }

    // Methods
    // -------

    // pub fn set_window_size() // TODO(remy): implement me and unit test me

    // TODO(remy): comment me
    // TODO(remy): unit test me (at least to validate that there is no leaks)
    pub fn render(self: Editor) void {
        var draw_list = c.igGetWindowDrawList();

        // self.renderCursor(draw_list);
        self.renderLines(draw_list);
    }

    // fn renderCursor(_: Editor, draw_list: *c.ImDrawList) void {
    // CIMGUI_API void ImDrawList_AddRectFilled(ImDrawList* self,const ImVec2 p_min,const ImVec2 p_max,ImU32 col,float rounding,ImDrawFlags flags);
    // c.ImDrawList_AddCircleFilled(draw_list, ImVec2(0.1, 0.1), 1.0, 0xFFFFFFFF, 50);
    // }

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

// TODO(remy): unit test me
