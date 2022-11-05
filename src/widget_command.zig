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
        var rv = WidgetCommand{
            .buff = undefined,
        };
        rv.reset();
        return rv;
    }

    // Methods
    // -------

    pub fn interpret(self: *WidgetCommand, app: *App) void {
        std.log.debug("WidgetCommand.interpret. buff: {s}", .{self.buff});
        // quit
        if (std.mem.eql(u8, self.buff[0..3], ":q!")) {
            app.quit();
        }
        if (std.mem.eql(u8, self.buff[0..6], ":debug")) {
            var widget_text = app.currentWidgetText();
            std.log.debug("File opened: {s}, lines count: {d}", .{ widget_text.editor.buffer.filepath.bytes(), widget_text.editor.buffer.lines.items.len });
            std.log.debug("Viewport: {}", .{widget_text.viewport});
            std.log.debug("History entries count: {d}", .{widget_text.editor.history.items.len});
            std.log.debug("History entries:\n{}", .{widget_text.editor.history});
            std.log.debug("Cursor position: {}", .{widget_text.cursor.pos});
            if (widget_text.editor.buffer.getLine(widget_text.cursor.pos.b)) |line| {
                if (line != undefined) {
                    std.log.debug("Line size: {d}", .{line.size()});
                    std.log.debug("Line content:\n{s}", .{line.bytes()});
                } else {
                    std.log.debug("Line: undefined", .{});
                }
            } else |err| {
                std.log.debug("Line errored while using getLine: {}", .{err});
            }
        }
        self.reset();
    }

    pub fn reset(self: *WidgetCommand) void {
        self.buff = std.mem.zeroes([8192]u8);
    }

    // Functions
    // ---------

    pub fn callback(_: [*c]c.ImGuiInputTextCallbackData) callconv(.C) c_int {
        // we don't use it for now, here for later usage.
        return 0;
    }
};
