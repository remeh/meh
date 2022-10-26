const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;

// TODO(remy): comment
pub const WidgetCommand = struct {
    buff: [8192]u8,

    // Constructors
    // ------------

    pub fn init() WidgetCommand {
        return WidgetCommand{
            .buff = std.mem.zeroes([8192]u8),
        };
    }

    // Methods
    // -------
    pub fn interpret(self: *WidgetCommand, app: *App) void {
        std.log.debug("WidgetCommand.interpret. buff: {s}", .{self.buff});

        // quit
        if (std.mem.eql(u8, self.buff[0..3], ":q!")) {
            app.quit();
        }

        self.buff = std.mem.zeroes([8192]u8);
    }

    // Functions
    // ---------

    pub fn callback(_: [*c]c.ImGuiInputTextCallbackData) callconv(.C) c_int {
        // we don't use it for now, here for later usage.
        return 0;
    }
};
