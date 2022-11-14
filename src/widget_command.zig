const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const char_space = @import("widget_text.zig").char_space;

const WidgetCommandError = error{
    ArgsOutOfBounds,
};

// TODO(remy): comment
pub const WidgetCommand = struct {
    buff: [8192]u8,

    // Constructors
    // ------------

    pub fn init() WidgetCommand {
        var rv = WidgetCommand{
            .buff = std.mem.zeroes([8192]u8),
        };
        rv.reset();
        return rv;
    }

    // Methods
    // -------

    pub fn interpret(self: *WidgetCommand, app: *App) void {
        var command = self.getArg(0) catch {
            return;
        };

        // quit
        if (std.mem.eql(u8, command, "q") or std.mem.eql(u8, command, "q!")) {
            app.quit();
        }

        // write
        if (std.mem.eql(u8, command, "w")) {
            var wt = app.currentWidgetText();
            wt.editor.buffer.writeOnDisk() catch |err| {
                std.log.err("WidgetCommand.interpret: can't execute {s}: {}", .{ self.buff, err });
            };
        }

        // open file
        if (std.mem.eql(u8, command, "o")) {
            if (self.countArgs() < 2) {
                // TODO(remy): report errors in the app instead of in console
                std.log.err("WidgetCommand.interpret: not enough arguments for 'o'", .{});
                return;
            }
            if (self.getArg(1)) |f| {
                app.openFile(f) catch |err| {
                    std.log.err("WidgetCommand.interpret: can't open file: {}", .{err});
                };
                std.log.debug("{d}", .{app.editors.items.len});
            } else |_| {}
        }

        // go to line
        if (command.len > 1 and std.mem.eql(u8, command[0..1], ":")) {
            // read the line number
            if (std.fmt.parseInt(usize, command[1..command.len], 10)) |line_number| {
                var wt = app.currentWidgetText();
                wt.goToLine(line_number, true);
            } else |err| {
                std.log.warn("WidgetCommand.interpret: can't read line number: {}", .{err});
            }
        }

        // debug
        if (std.mem.eql(u8, command, "debug")) {
            var widget_text = app.currentWidgetText();
            std.log.debug("File opened: {s}, lines count: {d}", .{ widget_text.editor.buffer.filepath.bytes(), widget_text.editor.buffer.lines.items.len });
            std.log.debug("Window size: {}", .{app.window_size});
            std.log.debug("One char size: {}", .{app.oneCharSize()});
            std.log.debug("Viewport: {}", .{widget_text.viewport});
            std.log.debug("History entries count: {d}", .{widget_text.editor.history.items.len});
            std.log.debug("History entries:\n{}", .{widget_text.editor.history});
            std.log.debug("Cursor position: {}", .{widget_text.cursor.pos});
            if (widget_text.editor.buffer.getLine(widget_text.cursor.pos.b)) |line| {
                if (line != undefined) {
                    std.log.debug("Line size: {d}, utf8 size: {any}", .{ line.size(), line.utf8size() });
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

    /// countArgs returns how many arguments there currently is in the buff.
    /// The first one (the command) is part of this total.
    fn countArgs(self: WidgetCommand) usize {
        var rv: usize = 1;
        var i: usize = 0;
        var was_space = false;
        while (i < self.buff.len) : (i += 1) {
            if (self.buff[i] == 0) {
                return rv;
            }
            if (self.buff[i] == char_space) {
                was_space = true;
            } else {
                if (was_space) {
                    rv += 1;
                }
                was_space = false;
            }
        }
        return 0;
    }

    /// getArg returns the arg at the given position.
    /// Starts at 0, 0 being the command.
    fn getArg(self: WidgetCommand, idx: usize) ![]const u8 {
        if (idx > self.countArgs()) {
            return WidgetCommandError.ArgsOutOfBounds;
        }

        // find the end
        var size: usize = 0;
        while (size < self.buff.len) : (size += 1) {
            if (self.buff[size] == 0) {
                break;
            }
        }

        var arg: ?[]const u8 = undefined;
        var it = std.mem.split(u8, self.buff[0..size], " ");
        var i: usize = 0;
        arg = it.first();
        while (arg != null) {
            if (arg.?.len == 0) {
                arg = it.next();
                continue;
            }
            if (i == idx) {
                return arg.?;
            }
            i += 1;
            arg = it.next();
        }

        return WidgetCommandError.ArgsOutOfBounds;
    }
};

test "widget_command get args" {
    var wc = WidgetCommand{
        .buff = std.mem.zeroes([8192]u8),
    };
    std.mem.copy(u8, &wc.buff, "q");
    try expect(wc.countArgs() == 1);
    std.mem.copy(u8, &wc.buff, "o file.zig");
    try expect(wc.countArgs() == 2);
    std.mem.copy(u8, &wc.buff, "o  file.zig   file2.zig  file3.zig ");
    try expect(wc.countArgs() == 4);
    try expect(std.mem.eql(u8, try wc.getArg(0), "o"));
    try expect(std.mem.eql(u8, try wc.getArg(1), "file.zig"));
    try expect(std.mem.eql(u8, try wc.getArg(2), "file2.zig"));
    try expect(std.mem.eql(u8, try wc.getArg(3), "file3.zig"));
    try expect(wc.getArg(4) == WidgetCommandError.ArgsOutOfBounds);
}
