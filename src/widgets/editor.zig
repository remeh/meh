const std = @import("std");

// TODO(remy): comment me
pub const Line = struct {}

// TODO(remy): comment me
pub const Editor struct = {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(Line),

    // Constructors
    // ------------

    pub fn initEmpty(allocator: std.mem.Allocator) !Editor {
        return Editor{
            .allocator = allocator,
            .lines = std.ArrayList.init(allocator),
        };
    }

    pub fn deinit(self: *Editor) {
        editor.lines.deinit();
    }

    // Methods
    // -------

    // TODO(remy): comment me
    // TODO(remy): unit test me (at least to validate that there is no leaks)
    pub fn Render(self: Editor) { }
};

// TODO(remy): unit test me
