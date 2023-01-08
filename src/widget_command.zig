const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const Direction = @import("app.zig").Direction;
const Draw = @import("draw.zig").Draw;
const Font = @import("font.zig").Font;
const Ripgrep = @import("ripgrep.zig").Ripgrep;
const Scaler = @import("scaler.zig").Scaler;
const SearchDirection = @import("editor.zig").SearchDirection;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;
const WidgetInput = @import("widget_input.zig").WidgetInput;
const WidgetTextEdit = @import("widget_text_edit.zig").WidgetTextEdit;

const char_space = @import("u8slice.zig").char_space;

pub const WidgetCommandError = error{
    ArgsOutOfBounds,
    UnknownCommand,
};

/// WidgetCommand is used to input commands to interpret or execute.
pub const WidgetCommand = struct {
    allocator: std.mem.Allocator,
    input: WidgetInput,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetCommand {
        var rv = WidgetCommand{
            .allocator = allocator,
            .input = try WidgetInput.init(allocator),
        };
        return rv;
    }

    pub fn deinit(self: *WidgetCommand) void {
        self.input.deinit();
    }

    // Events
    // ------

    pub fn onBackspace(self: *WidgetCommand) void {
        self.input.onBackspace();
    }

    pub fn onTextInput(self: *WidgetCommand, txt: []const u8) void {
        _ = self.input.onTextInput(txt);
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
        // overlay
        Draw.fillRect(
            sdl_renderer,
            scaler,
            Vec2u{ .a = 0, .b = 0 },
            window_scaled_size,
            Vec4u{ .a = 20, .b = 20, .c = 20, .d = 130 },
        );

        // text edit background
        Draw.fillRect(
            sdl_renderer,
            scaler,
            draw_pos,
            widget_size,
            Vec4u{ .a = 20, .b = 20, .c = 20, .d = 240 },
        );

        var margin: Vec2u = Vec2u{ .a = 15, .b = 15 };

        // text edit
        var pos = draw_pos;
        pos.a += margin.a;
        pos.b += margin.b;
        self.input.render(
            sdl_renderer,
            font,
            scaler,
            pos,
            widget_size,
            one_char_size,
        );
    }

    pub fn interpret(self: *WidgetCommand, app: *App) !void {
        var prompt = self.getArg(0);

        if (prompt == null) {
            return;
        }

        var command = prompt.?;

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
                app.showMessageBoxError("Not enough argument for 'o'.", .{});
                return;
            }
            if (self.getArg(1)) |f| {
                app.openFile(f) catch |err| {
                    std.log.err("WidgetCommand.interpret: can't open file: {}", .{err});
                };
            }
            return;
        }

        // close file
        // ----------

        if (std.mem.eql(u8, command, ":bd")) {
            app.closeCurrentFile();
            return;
        }

        // toggle the split
        // ----------------

        if (std.mem.eql(u8, command, ":split")) {
            app.toggleSplit();
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
                    if (self.getArg(i)) |arg| {
                        try str.appendConst(" ");
                        try str.appendConst(arg);
                    }
                }
            }

            var wt = app.currentWidgetTextEdit();
            wt.search(str, SearchDirection.After, true);
            return;
        }

        // ripgrep
        // -------

        if (std.mem.eql(u8, command, ":rg")) {
            if (self.countArgs() == 1) {
                var text_edit = app.currentWidgetTextEdit();
                var word = try text_edit.editor.wordAt(text_edit.cursor.pos);
                var results = Ripgrep.search(app.allocator, word, app.working_dir.bytes()) catch |err| {
                    std.log.err("WidgetCommand: can't exec 'rg {s}': {}", .{ word, err });
                    return;
                };
                app.openRipgrepResults(results);
                return;
            }
            if (self.rest(1)) |parameters| {
                var results = Ripgrep.search(app.allocator, parameters, app.working_dir.bytes()) catch |err| {
                    std.log.err("WidgetCommand: can't exec 'rg {s}': {}", .{ parameters, err });
                    return;
                };
                app.openRipgrepResults(results);
                return;
            }
            return;
        }

        // lsp commands
        // ------------

        if (std.mem.eql(u8, command, ":ref")) {
            if (app.lsp) |lsp| {
                lsp.references(&(app.currentWidgetTextEdit().editor.buffer), app.currentWidgetTextEdit().cursor.pos) catch |err| {
                    std.log.err("WidgetCommand: can't exec ':ref': {}", .{err});
                    return;
                };
            } else {
                app.showMessageBoxError("LSP not initialized.", .{});
            }
            return;
        }

        if (std.mem.eql(u8, command, ":def")) {
            if (app.lsp) |lsp| {
                lsp.definition(&(app.currentWidgetTextEdit().editor.buffer), app.currentWidgetTextEdit().cursor.pos) catch |err| {
                    std.log.err("WidgetCommand: can't exec ':def': {}", .{err});
                    return;
                };
            } else {
                app.showMessageBoxError("LSP not initialized.", .{});
            }
            return;
        }

        // debug
        // -----

        if (std.mem.eql(u8, command, ":debug")) {
            var widget_text_edit = app.currentWidgetTextEdit();
            std.log.debug("File opened: {s}, lines count: {d}", .{ widget_text_edit.editor.buffer.fullpath.bytes(), widget_text_edit.editor.buffer.lines.items.len });
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
                wt.goToLine(line_number, .Center);
                return;
            } else |_| {
                // it's not a number, let's continue
            }
        }

        self.input.reset();
        return WidgetCommandError.UnknownCommand;
    }

    pub fn reset(self: *WidgetCommand) void {
        self.input.reset();
    }

    /// onArrow is called when an arrow key is pressed to move the cursor.
    /// hjkl are redirected to this method.
    pub fn onArrowKey(self: *WidgetCommand, direction: Direction) void {
        self.input.onArrowKey(direction);
    }

    /// countArgs returns how many arguments there currently is in the buff.
    /// The first one (the command) is part of this total.
    fn countArgs(self: WidgetCommand) usize {
        var rv: usize = 1;
        var i: usize = 0;
        var was_space = false;

        var line = self.input.text() catch |err| {
            std.log.err("WidgetCommand.countArgs: can't get line 0: {}", .{err});
            return 0;
        };
        var buff = line.bytes();

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
    fn getArg(self: WidgetCommand, idx: usize) ?[]const u8 {
        if (idx > self.countArgs()) {
            return null;
        }

        var line = self.input.text() catch {
            return null;
        };
        var buff = line.bytes();

        // find the end
        var size: usize = 0;
        while (size < buff.len) : (size += 1) {
            if (buff[size] == 0) {
                break;
            }
        }

        var arg: ?[]const u8 = undefined;
        var it = std.mem.split(u8, buff[0..size], " "); // TODO(remy): use tokenize instead
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

        return null;
    }

    /// rest returns the rest of the input starting at the given parameter,
    /// useful to feed it to an external tool such as ripgrep or fd.
    fn rest(self: WidgetCommand, idx: usize) ?[]const u8 {
        if (idx > self.countArgs()) {
            return null;
        }

        var line = self.input.text() catch {
            return null;
        };
        var buff = line.bytes();

        var i: usize = 0;
        var n_count: usize = 0;
        while (i < buff.len) : (i += 1) {
            if (buff[i] == ' ') {
                n_count += 1;
                if (n_count == idx) {
                    return buff[i + 1 ..];
                }
            }
        }

        return buff[i..];
    }
};

test "widget_command count args" {
    const allocator = std.testing.allocator;
    var command = try WidgetCommand.init(allocator);
    defer command.deinit();

    command.onTextInput("command to👻 run");
    try expect(std.mem.eql(u8, (try command.input.text()).bytes(), "command to👻 run"));

    try expect(command.countArgs() == 3);
}

test "widget_command args" {
    const allocator = std.testing.allocator;
    var command = try WidgetCommand.init(allocator);
    defer command.deinit();

    command.onTextInput("command to👻 run");
    try expect(std.mem.eql(u8, (try command.input.text()).bytes(), "command to👻 run"));

    var arg = command.getArg(0);
    try expect(arg != null);
    try expect(std.mem.eql(u8, arg.?, "command"));

    arg = command.getArg(1);
    try expect(arg != null);
    try expect(std.mem.eql(u8, arg.?, "to👻"));

    arg = command.getArg(2);
    try expect(arg != null);
    try expect(std.mem.eql(u8, arg.?, "run"));
}

test "widget_command rest" {
    const allocator = std.testing.allocator;
    var command = try WidgetCommand.init(allocator);
    defer command.deinit();

    command.onTextInput("command to👻 run");
    try expect(std.mem.eql(u8, (try command.input.text()).bytes(), "command to👻 run"));

    var params = command.rest(1);
    try expect(params != null);
    try expect(std.mem.eql(u8, params.?, "to👻 run"));

    params = command.rest(2);
    try expect(params != null);
    try expect(std.mem.eql(u8, params.?, "run"));
}
