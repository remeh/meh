const std = @import("std");

const Buffer = @import("../buffer.zig").Buffer;
const c = @import("../clib.zig").c;
const Vec2i = @import("../vec.zig").Vec2i;

// TODO(remy): comment me
pub const Line = struct {};

// TODO(remy): comment me
pub const Editor = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(Line),
    buffer: Buffer,
    visible_lines: Vec2i,

    // Constructors
    // ------------

    // TODO(remy): comment me
    pub fn initEmpty(allocator: std.mem.Allocator) Editor {
        return Editor{
            .allocator = allocator,
            .lines = std.ArrayList(Line).init(allocator),
            .buffer = Buffer.initEmpty(allocator),
            .visible_lines = undefined,
        };
    }

    // TODO(remy): comment me
    pub fn initWithBuffer(allocator: std.mem.Allocator, buffer: Buffer) Editor {
        return Editor{
            .allocator = allocator,
            .lines = std.ArrayList(Line).init(allocator),
            .buffer = buffer,
            .visible_lines = Vec2i{ .a = 0, .b = @intCast(i64, buffer.lineReturns.items.len) },
        };
    }

    pub fn deinit(self: *Editor) void {
        self.lines.deinit();
        self.buffer.deinit();
    }

    // Methods
    // -------

    // TODO(remy): comment me
    // TODO(remy): unit test me (at least to validate that there is no leaks)
    pub fn Render(self: Editor) void {
        var i: usize = @intCast(usize, self.visible_lines.a);
        while (i < self.visible_lines.b) : (i += 1) {
            if (self.buffer.getLinePos(i)) |pos| {
                var buff: []u8 = self.buffer.data.items[@intCast(usize, pos.a) .. @intCast(usize, pos.b) + 1];
                buff[buff.len - 1] = 0; // finish the buffer with a 0 for the C-land
                c.igText(@ptrCast([*]const u8, buff));
            } else |_| {
                // TODO(remy): do something with the error
            }
        }
    }
};

// TODO(remy): unit test me
