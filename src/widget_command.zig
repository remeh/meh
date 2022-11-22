const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const Buffer = @import("buffer.zig").Buffer;
const Draw = @import("draw.zig").Draw;
const Editor = @import("editor.zig").Editor;
const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const WidgetTextEdit = @import("widget_text_edit.zig").WidgetTextEdit;
const Insert = @import("widget_text_edit.zig").Insert;
const char_space = @import("widget_text_edit.zig").char_space;

const WidgetCommandError = error{
    ArgsOutOfBounds,
};

// TODO(remy): comment
pub const WidgetCommand = struct {
    allocator: std.mem.Allocator,
    widget_text_edit: WidgetTextEdit,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetCommand {
        var rv = WidgetCommand{
            .allocator = allocator,
            .widget_text_edit = WidgetTextEdit.initWithBuffer(allocator, try Buffer.initEmpty(allocator)),
        };
        rv.widget_text_edit.draw_line_numbers = false;
        rv.widget_text_edit.editor.history_enabled = false;
        rv.widget_text_edit.viewport.lines.a = 0;
        rv.widget_text_edit.viewport.columns.a = 0;
        rv.widget_text_edit.setInputMode(.Insert);
        rv.reset();
        return rv;
    }

    pub fn deinit(self: *WidgetCommand) void {
        self.widget_text_edit.deinit();
    }

    // Events
    // ------

    // TODO(remy):
    // TODO(remy): comment
    pub fn onBackspace(self: *WidgetCommand) void {
        self.widget_text_edit.editor.deleteUtf8Char(self.widget_text_edit.cursor.pos, true) catch |err| {
            std.log.err("WidgetCommand.onBackspace: {}", .{err});
        };
        self.widget_text_edit.moveCursor(Vec2i{ .a = -1, .b = 0 }, true);
    }

    // Methods
    // -------

    pub fn render(
        self: *WidgetCommand,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        window_scaled_size: Vec2u,
        draw_pos: Vec2u,
        widget_size: Vec2u,
        one_char_size: Vec2u,
    ) void {
        self.widget_text_edit.viewport.lines.a = 0;
        self.widget_text_edit.viewport.lines.b = 1;

        // overlay
        Draw.fillRect(
            sdl_renderer,
            scaler,
            Vec2u{ .a = 0, .b = 0 },
            window_scaled_size,
            c.SDL_Color{ .r = 20, .g = 20, .b = 20, .a = 130 },
        );

        // text edit background
        Draw.fillRect(
            sdl_renderer,
            scaler,
            draw_pos,
            widget_size,
            c.SDL_Color{ .r = 20, .g = 20, .b = 20, .a = 240 },
        );

        // text edit
        var pos = draw_pos;
        pos.a += 15;
        pos.b += 15;
        self.widget_text_edit.render(
            sdl_renderer,
            font,
            scaler,
            pos,
            widget_size,
            one_char_size,
        );
    }

    pub fn interpret(self: *WidgetCommand, app: *App) !void {
        var command = self.getArg(0) catch {
            return;
        };

        // quit
        // ----

        if (std.mem.eql(u8, command, ":q") or std.mem.eql(u8, command, ":q!")) {
            app.quit();
            return;
        }

        // write
        // -----

        if (std.mem.eql(u8, command, ":w")) {
            var wt = app.currentWidgetTextEdit();
            wt.editor.save() catch |err| {
                std.log.err("WidgetCommand.interpret: can't execute {s}: {}", .{ command, err });
            };
            return;
        }

        // open file
        // ---------

        if (std.mem.eql(u8, command, ":o")) {
            if (self.countArgs() < 2) {
                // TODO(remy): report errors in the app instead of in console
                std.log.err("WidgetCommand.interpret: not enough arguments for 'o'", .{});
                return;
            }
            if (self.getArg(1)) |f| {
                app.openFile(f) catch |err| {
                    std.log.err("WidgetCommand.interpret: can't open file: {}", .{err});
                };
            } else |_| {}
            return;
        }

        // search
        // ------

        if (command.len > 1 and std.mem.eql(u8, command[0..1], "/")) {
            var str = try U8Slice.initFromSlice(app.allocator, command[1..command.len]);
            defer str.deinit();

            const args_count = self.countArgs();
            if (args_count > 1) {
                var i: usize = 1; // ignore the first one since it's the command
                while (i < args_count) : (i += 1) {
                    var arg = try self.getArg(i);
                    try str.appendConst(" ");
                    try str.appendConst(arg);
                }
            }

            std.log.debug("WidgetCommand.interpret: search for {s}", .{str.bytes()});
            var wt = app.currentWidgetTextEdit();
            wt.search(str);
            return;
        }

        // debug
        // -----

        if (std.mem.eql(u8, command, ":debug")) {
            var widget_text_edit = app.currentWidgetTextEdit();
            std.log.debug("File opened: {s}, lines count: {d}", .{ widget_text_edit.editor.buffer.filepath.bytes(), widget_text_edit.editor.buffer.lines.items.len });
            std.log.debug("Window pixel size: {}", .{app.window_pixel_size});
            std.log.debug("Window scaled size: {}", .{app.window_scaled_size});
            std.log.debug("Viewport: {}", .{widget_text_edit.viewport});
            std.log.debug("History entries count: {d}", .{widget_text_edit.editor.history.items.len});
            std.log.debug("History entries:\n{}", .{widget_text_edit.editor.history});
            std.log.debug("Cursor position: {}", .{widget_text_edit.cursor.pos});
            if (widget_text_edit.editor.buffer.getLine(widget_text_edit.cursor.pos.b)) |line| {
                if (line != undefined) {
                    std.log.debug("Line size: {d}, utf8 size: {any}", .{ line.size(), line.utf8size() });
                    std.log.debug("Line content:\n{s}", .{line.bytes()});
                } else {
                    std.log.debug("Line: undefined", .{});
                }
            } else |err| {
                std.log.debug("Line errored while using getLine: {}", .{err});
            }
            return;
        }

        // go to line
        // ----------

        if (command.len > 1 and std.mem.eql(u8, command[0..1], ":")) {
            // read the line number
            if (std.fmt.parseInt(usize, command[1..command.len], 10)) |line_number| {
                var wt = app.currentWidgetTextEdit();
                wt.goToLine(line_number, true);
            } else |err| {
                std.log.warn("WidgetCommand.interpret: can't read line number: {}", .{err});
            }
        }

        self.reset();
    }

    pub fn reset(self: *WidgetCommand) void {
        self.widget_text_edit.editor.buffer.lines.items[0].deinit();
        self.widget_text_edit.editor.buffer.lines.items[0] = U8Slice.initEmpty(self.allocator);
        self.widget_text_edit.cursor.pos.a = 0;
        self.widget_text_edit.cursor.pos.b = 0;
    }

    // Functions
    // ---------

    /// countArgs returns how many arguments there currently is in the buff.
    /// The first one (the command) is part of this total.
    fn countArgs(self: WidgetCommand) usize {
        var rv: usize = 1;
        var i: usize = 0;
        var was_space = false;

        var line = self.widget_text_edit.editor.buffer.getLine(0) catch |err| {
            std.log.err("WidgetCommand.countArgs: can't get line 0: {}", .{err});
            return 0;
        };
        var buff = line.bytes();
        std.log.debug("{s}", .{buff});

        while (i < buff.len) : (i += 1) {
            if (buff[i] == 0) {
                return rv;
            }
            if (buff[i] == char_space) {
                was_space = true;
            } else {
                if (was_space) {
                    rv += 1;
                }
                was_space = false;
            }
        }
        return rv;
    }

    /// getArg returns the arg at the given position.
    /// Starts at 0, 0 being the command.
    fn getArg(self: WidgetCommand, idx: usize) ![]const u8 {
        if (idx > self.countArgs()) {
            return WidgetCommandError.ArgsOutOfBounds;
        }

        var line = try self.widget_text_edit.editor.buffer.getLine(0);
        var buff = line.bytes();

        // find the end
        var size: usize = 0;
        while (size < buff.len) : (size += 1) {
            if (buff[size] == 0) {
                break;
            }
        }

        var arg: ?[]const u8 = undefined;
        var it = std.mem.split(u8, buff[0..size], " ");
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
