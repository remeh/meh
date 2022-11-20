const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const Buffer = @import("buffer.zig").Buffer;
const Draw = @import("draw.zig").Draw;
const Editor = @import("editor.zig").Editor;
const EditorError = @import("editor.zig").EditorError;
const Font = @import("font.zig").Font;
const ImVec2 = @import("vec.zig").ImVec2;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const Vec2utoi = @import("vec.zig").Vec2utoi;

// TODO(remy): where should we define this?
// TODO(remy): comment
// TODO(remy): comment
pub const char_offset_before_move = 5;
// TODO(remy): comment
pub const tab_spaces = 4;
pub const char_space = ' ';
pub const string_space = " ";

pub const InputMode = enum {
    Command,
    Insert,
    Replace,
};

pub const CursorMove = enum {
    EndOfLine,
    StartOfLine,
    EndOfWord,
    StartOfWord,
    StartOfBuffer,
    EndOfBuffer,
    NextSpace,
    PreviousSpace,
    NextLine,
    PreviousLine,
    /// RespectPreviousLineIndent replicates previous line indentation on the current one.
    RespectPreviousLineIndent,
    /// AfterIndentation moves the cursor right until it is not on a space
    AfterIndentation,
};

// TODO(remy): comment
pub const Cursor = struct {
    /// pos is the position relative to the editor
    /// This one is not dependant of utf8. 1 right means 1 character right, would it be
    /// an utf8 chars needing 3 bytes or one needing 1 byte.
    pos: Vec2u,

    // Constructors
    // ------------

    pub fn init() Cursor {
        return Cursor{
            .pos = Vec2u{ .a = 0, .b = 0 },
        };
    }

    // Methods
    // -------

    /// `render` renders the cursor in the `WidgetTextEdit`.
    // TODO(remy): consider redrawing the character which is under the cursor in a reverse color to see it above the cursor
    /// `line_offset_in_buffer` contains the first visible line (of the buffer) in the current window. With this + the position
    /// of the cursor in the buffer, we can compute where to relatively position the cursor in the window in order to draw it.
    pub fn render(self: Cursor, sdl_renderer: *c.SDL_Renderer, input_mode: InputMode, viewport: WidgetTextEditViewport, scaler: Scaler, draw_pos: Vec2u, font_size: Vec2u) void {
        var col_offset_in_buffer = viewport.columns.a;
        var line_offset_in_buffer = viewport.lines.a;

        switch (input_mode) {
            .Insert => {
                Draw.fill_rect(
                    sdl_renderer,
                    scaler,
                    Vec2u{
                        .a = draw_pos.a + (self.pos.a - col_offset_in_buffer) * font_size.a,
                        .b = draw_pos.b + (self.pos.b - line_offset_in_buffer) * font_size.b,
                    },
                    Vec2u{ .a = 2, .b = font_size.b },
                    c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 },
                );
            },
            else => {
                Draw.fill_rect(
                    sdl_renderer,
                    scaler,
                    Vec2u{
                        .a = draw_pos.a + (self.pos.a - col_offset_in_buffer) * font_size.a,
                        .b = draw_pos.b + (self.pos.b - line_offset_in_buffer) * font_size.b,
                    },
                    Vec2u{ .a = font_size.a, .b = font_size.b },
                    c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 },
                );
            },
        }
    }

    /// isVisible returns true if the cursor is visible in the given viewport.
    pub fn isVisible(self: Cursor, viewport: WidgetTextEditViewport) bool {
        return (self.pos.b >= viewport.lines.a and self.pos.b <= viewport.lines.b and
            self.pos.a >= viewport.columns.a and self.pos.a <= viewport.columns.b);
    }
};

pub const WidgetTextEditViewport = struct {
    lines: Vec2u,
    columns: Vec2u,
};

pub const SelectionState = enum {
    Inactive,
    KeyboardSelection,
    MouseSelection,
    Active,
};

pub const WidgetTextEditSelection = struct {
    initial: Vec2u,
    start: Vec2u,
    stop: Vec2u,
    state: SelectionState,
};

// TODO(remy): comment
pub const WidgetTextEdit = struct {
    allocator: std.mem.Allocator,
    cursor: Cursor, // TODO(remy): replace me with a custom (containing cursor mode)
    draw_line_numbers: bool,
    editor: Editor,
    input_mode: InputMode,
    // TODO(remy): comment
    viewport: WidgetTextEditViewport,
    selection: WidgetTextEditSelection,
    selection_left_offset: usize, // when rendering the line number, it creates a left offset
    visible_cols_and_lines: Vec2u,
    one_char_size: Vec2u, // refreshed before every frame

    // Constructors
    // ------------

    // TODO(remy): comment
    pub fn initWithBuffer(allocator: std.mem.Allocator, buffer: Buffer) WidgetTextEdit {
        return WidgetTextEdit{
            .allocator = allocator,
            .cursor = Cursor.init(),
            .draw_line_numbers = true,
            .editor = Editor.init(allocator, buffer),
            .input_mode = InputMode.Insert,
            .one_char_size = Vec2u{ .a = 16, .b = 8 },
            .viewport = WidgetTextEditViewport{
                .columns = Vec2u{ .a = 0, .b = 1 },
                .lines = Vec2u{ .a = 0, .b = 1 },
            },
            .visible_cols_and_lines = Vec2u{ .a = 1, .b = 1 },
            .selection_left_offset = 0,
            .selection = WidgetTextEditSelection{
                .start = Vec2u{ .a = 0, .b = 0 },
                .initial = Vec2u{ .a = 0, .b = 0 },
                .stop = Vec2u{ .a = 0, .b = 0 },
                .state = .Inactive,
            },
        };
    }

    pub fn deinit(self: *WidgetTextEdit) void {
        self.editor.deinit();
    }

    // Rendering methods
    // -----------------

    // TODO(remy): comment
    // TODO(remy): unit test (at least to validate that there is no leaks)
    /// All positions must be given like if scaling (retina/highdpi) doesn't exist. The scale will be applied internally.
    pub fn render(self: *WidgetTextEdit, sdl_renderer: *c.SDL_Renderer, font: Font, scaler: Scaler, draw_pos: Vec2u, widget_size: Vec2u, one_char_size: Vec2u) void {
        self.one_char_size = one_char_size;
        self.visible_cols_and_lines = Vec2u{
            .a = (widget_size.a - draw_pos.a) / @floatToInt(usize, @intToFloat(f32, one_char_size.a)),
            .b = (widget_size.b - draw_pos.b) / @floatToInt(usize, @intToFloat(f32, one_char_size.b)),
        };
        self.computeViewport();

        var pos = draw_pos;

        // rendering line numbers create a left offset
        var left_offset: usize = 0;

        if (self.draw_line_numbers) {
            left_offset = self.renderLineNumbers(sdl_renderer, font, scaler, pos, widget_size, one_char_size);
            pos.a += left_offset;
        }

        // so does rendering lines (which adds a small blank)
        left_offset = self.renderLines(font, scaler, pos);
        pos.a += left_offset;

        self.selection_left_offset = pos.a;

        self.renderSelection(sdl_renderer, scaler, pos);
        self.renderCursor(sdl_renderer, scaler, pos, one_char_size);
    }

    fn renderCursor(self: WidgetTextEdit, sdl_renderer: *c.SDL_Renderer, scaler: Scaler, draw_pos: Vec2u, one_char_size: Vec2u) void {
        if (self.cursor.isVisible(self.viewport)) {
            self.cursor.render(sdl_renderer, self.input_mode, self.viewport, scaler, draw_pos, one_char_size);
        }
    }

    /// Returns x offset introduced by drawing the lines numbers
    fn renderLineNumbers(self: WidgetTextEdit, sdl_renderer: *c.SDL_Renderer, font: Font, scaler: Scaler, draw_pos: Vec2u, widget_size: Vec2u, one_char_size: Vec2u) usize {
        var text_pos_x: usize = 10;

        var carray: [128]u8 = std.mem.zeroes([128]u8);
        var cbuff = &carray;

        var i: usize = self.viewport.lines.a;
        var y_offset: usize = draw_pos.b;

        // measure how wide we need this block to be

        var max_digits: usize = 1;
        var line_count = self.editor.linesCount();
        while (line_count / 10 > 0) {
            max_digits += 1;
            line_count /= 10;
        }
        var width = (max_digits + 2) * one_char_size.a;

        // render the background

        Draw.fill_rect(
            sdl_renderer,
            scaler,
            Vec2u{ .a = draw_pos.a, .b = draw_pos.b },
            Vec2u{ .a = draw_pos.a + width, .b = widget_size.b - draw_pos.b },
            c.SDL_Color{ .r = 20, .g = 20, .b = 20, .a = 255 },
        );

        // render the line numbers

        while (i < self.viewport.lines.b and i < self.editor.buffer.lines.items.len) : (i += 1) {
            _ = std.fmt.bufPrintZ(cbuff, "{d}", .{i + 1}) catch |err| {
                std.log.err("WidgetTextEdit.renderLineNumbers: can't render line number {}: {}", .{ i, err });
                return 0;
            };

            if (i == self.cursor.pos.b) {
                Draw.fill_rect(
                    sdl_renderer,
                    scaler,
                    Vec2u{ .a = draw_pos.a, .b = y_offset },
                    Vec2u{ .a = draw_pos.a + width, .b = self.one_char_size.b },
                    c.SDL_Color{ .r = 120, .g = 120, .b = 120, .a = 255 },
                );
            }

            Draw.draw_text(
                font,
                scaler,
                Vec2u{ .a = text_pos_x, .b = y_offset },
                cbuff,
            );

            y_offset += self.one_char_size.b;
        }

        return width;
    }

    fn renderLines(self: WidgetTextEdit, font: Font, scaler: Scaler, draw_pos: Vec2u) usize {
        var i: usize = self.viewport.lines.a;
        var j: usize = self.viewport.columns.a;
        var y_offset: usize = 0;
        var left_blank_offset: usize = 5;

        while (i < self.viewport.lines.b) : (i += 1) {
            j = self.viewport.columns.a;
            if (self.editor.buffer.getLine(i)) |line| {
                var buff: *[]u8 = &line.data.items; // uses a pointer only to avoid a copy

                // empty line
                if (buff.len == 0 or (buff.len == 1 and buff.*[0] == '\n') or buff.len < self.viewport.columns.a) {
                    y_offset += self.one_char_size.b;
                    continue;
                }

                var data = line.bytes()[self.viewport.columns.a..@min(self.viewport.columns.b, line.size())];
                Draw.draw_text(
                    font,
                    scaler,
                    Vec2u{ .a = draw_pos.a + left_blank_offset, .b = draw_pos.b + y_offset },
                    data,
                );

                y_offset += self.one_char_size.b;
            } else |_| {
                // TODO(remy): do something with the error
            }
        }

        return left_blank_offset;
    }

    fn renderSelection(self: WidgetTextEdit, sdl_renderer: *c.SDL_Renderer, scaler: Scaler, draw_pos: Vec2u) void {
        if (self.selection.state == .Inactive) {
            return;
        }

        var i: usize = self.viewport.lines.a;
        var y_offset: usize = 0;

        while (i < self.viewport.lines.b) : (i += 1) {
            if (self.editor.buffer.getLine(i)) |line| {
                var utf8size = line.utf8size() catch |err| {
                    std.log.err("WidgetTextEdit.renderSelection: can't get utf8size of line {d}: {}", .{ i, err });
                    return;
                };

                var viewport_x_offset = self.viewport.columns.a * self.one_char_size.a;

                if (i >= self.selection.start.b and i <= self.selection.stop.b) {
                    var start_x = draw_pos.a;
                    // start of the line or not?
                    if (self.selection.start.b == i) {
                        start_x += self.selection.start.a * self.one_char_size.a - viewport_x_offset;
                    }
                    // end of the line or not?
                    var end_x = draw_pos.a + (utf8size - 1) * self.one_char_size.a - viewport_x_offset;
                    if (self.selection.stop.b == i) {
                        end_x = draw_pos.a + self.selection.stop.a * self.one_char_size.a - viewport_x_offset;
                    }

                    var width: i64 = @max(@intCast(i64, end_x) - @intCast(i64, start_x), 0);

                    Draw.fill_rect(
                        sdl_renderer,
                        scaler,
                        Vec2u{ .a = start_x, .b = draw_pos.b + y_offset },
                        Vec2u{ .a = @intCast(usize, width), .b = self.one_char_size.b },
                        c.SDL_Color{ .r = 175, .g = 175, .b = 175, .a = 100 },
                    );
                }
                y_offset += self.one_char_size.b;
            } else |err| {
                std.log.err("WidgetTextEdit.renderSelection: can't get line {d}: {}", .{ i, err });
                return;
            }
        }

        return;
    }

    /// computeViewport is dependant on visible_cols_and_lines, which is computed every
    /// render (since it needs a pos and a size, provided to the widget on rendering).
    fn computeViewport(self: *WidgetTextEdit) void {
        self.viewport.columns.b = self.viewport.columns.a + self.visible_cols_and_lines.a;
        self.viewport.lines.b = self.viewport.lines.a + self.visible_cols_and_lines.b;
    }

    /// scrollToCursor scrolls to the cursor if it is not visible.
    // TODO(remy): unit test
    fn scrollToCursor(self: *WidgetTextEdit) void {
        // the cursor is above
        if (self.cursor.pos.b < self.viewport.lines.a) {
            var count_lines_visible = self.viewport.lines.b - self.viewport.lines.a;
            self.viewport.lines.a = self.cursor.pos.b;
            self.viewport.lines.b = self.viewport.lines.a + count_lines_visible;
        }

        // the cursor is below
        if (self.cursor.pos.b + char_offset_before_move > self.viewport.lines.b) {
            var distance = self.cursor.pos.b + char_offset_before_move - self.viewport.lines.b;
            self.viewport.lines.a += distance;
            self.viewport.lines.b += distance;
        }

        // the cursor is on the left
        if (self.cursor.pos.a < self.viewport.columns.a) {
            var count_col_visible = self.viewport.columns.b - self.viewport.columns.a;
            self.viewport.columns.a = self.cursor.pos.a;
            self.viewport.columns.b = self.viewport.columns.a + count_col_visible;
        }

        // the cursor is on the right
        if (self.cursor.pos.a + char_offset_before_move > self.viewport.columns.b) {
            var distance = self.cursor.pos.a + char_offset_before_move - self.viewport.columns.b;
            self.viewport.columns.a += distance;
            self.viewport.columns.b += distance;
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    fn cursorPosFromWindowPos(self: WidgetTextEdit, click_window_pos: Vec2u, draw_pos: Vec2u) Vec2u {
        var rv = Vec2u{ .a = 0, .b = 0 };

        // remove the offset
        var in_editor = Vec2u{
            .a = @intCast(usize, @max(@intCast(i64, click_window_pos.a - draw_pos.a) - @intCast(i64, self.selection_left_offset), 0)),
            .b = click_window_pos.b - draw_pos.b,
        };

        rv.a = in_editor.a / self.one_char_size.a;
        rv.b = in_editor.b / self.one_char_size.b;

        rv.a += self.viewport.columns.a;
        rv.b += self.viewport.lines.a;

        return rv;
    }

    fn setCursorPos(self: *WidgetTextEdit, pos: Vec2u, scroll: bool) void {
        self.cursor.pos = pos;
        if (scroll) {
            self.scrollToCursor();
        }
    }

    pub fn search(self: *WidgetTextEdit, txt: U8Slice) void {
        if (self.editor.search(txt, self.cursor.pos, false)) |new_cursor_pos| {
            self.setCursorPos(new_cursor_pos, true);
        } else |err| {
            std.log.warn("WidgetCommand.interpret: can't search for '{s}' in document '{s}': {}", .{ txt.bytes(), self.editor.buffer.filepath.bytes(), err });
        }
    }

    // TODO(remy): unit test
    fn startSelection(self: *WidgetTextEdit, cursor_pos: Vec2u, state: SelectionState) void {
        self.setInputMode(.Command);

        self.selection.start = cursor_pos;
        self.selection.initial = self.selection.start;
        self.selection.stop = self.selection.start;

        self.selection.state = state;
    }

    // TODO(remy): unit test
    fn updateSelection(self: *WidgetTextEdit, cursor_pos: Vec2u) void {
        if (self.selection.state == .MouseSelection or self.selection.state == .KeyboardSelection) {
            if (cursor_pos.b < self.selection.initial.b or (cursor_pos.b == self.selection.initial.b and cursor_pos.a < self.selection.initial.a)) {
                self.selection.start = cursor_pos;
                self.selection.stop = self.selection.initial;
            } else {
                self.selection.start = self.selection.initial;
                self.selection.stop = cursor_pos;
            }
        }
    }

    // TODO(remy): unit test
    fn stopSelection(self: *WidgetTextEdit, next_state: SelectionState) void {
        if (self.selection.state == .Inactive) {
            return;
        }

        // selection has stopped where it has been initiated, consider this as a click.
        if (self.selection.state == .MouseSelection and
            self.selection.stop.a == self.selection.start.a and
            self.selection.stop.b == self.selection.start.b)
        {
            self.setCursorPos(self.selection.initial, false);
            // make sure the position is on text
            self.validateCursorPosition(true);
            // selection inactive
            self.selection.state = .Inactive;
            // enter insert mode
            self.setInputMode(.Insert);
            return;
        }

        self.selection.state = next_state;
    }

    // TODO(remy): unit test
    pub fn paste(self: *WidgetTextEdit) !void {
        // read data from the clipboard
        var data = c.SDL_GetClipboardText();
        defer c.SDL_free(data);
        // turn into an U8Slice
        var str = try U8Slice.initFromCSlice(self.allocator, data);
        defer str.deinit();
        // paste in the editor
        var new_cursor_pos = try self.editor.paste(self.cursor.pos, str);
        // move the cursor
        self.setCursorPos(new_cursor_pos, true);
    }

    // Events methods
    // --------------

    /// onCtrlKeyDown is called when a key has been pressed while a ctrl key is held down.
    pub fn onCtrlKeyDown(self: *WidgetTextEdit, keycode: i32, ctrl: bool, cmd: bool) bool {
        _ = ctrl;
        _ = cmd;

        var move = @divTrunc(@intCast(i64, self.viewport.lines.b) - @intCast(i64, self.viewport.lines.a), 2);
        if (move < 0) {
            move = 8;
        }

        switch (keycode) {
            'd' => {
                self.moveCursor(Vec2i{ .a = 0, .b = move }, true);
            },
            'u' => {
                self.moveCursor(Vec2i{ .a = 0, .b = -move }, true);
            },
            'v' => {
                self.paste() catch |err| {
                    std.log.err("WidgetTextEdit.onCtrlKeyDown: can't paste: {}", .{err});
                };
                return true;
            },
            else => {},
        }
        return true;
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn onTextInput(self: *WidgetTextEdit, txt: []const u8) bool {
        switch (self.input_mode) {
            .Insert => {
                // TODO(remy): selection support
                if (self.editor.insertUtf8Text(self.cursor.pos, txt)) {
                    self.moveCursor(Vec2i{ .a = 1, .b = 0 }, true);
                } else |err| {
                    std.log.err("WidgetTextEdit.onTextInput: can't insert utf8 text: {}", .{err});
                }
            },
            else => {
                switch (txt[0]) {
                    // movements
                    'h' => self.moveCursor(Vec2i{ .a = -1, .b = 0 }, true),
                    'j' => self.moveCursor(Vec2i{ .a = 0, .b = 1 }, true),
                    'k' => self.moveCursor(Vec2i{ .a = 0, .b = -1 }, true),
                    'l' => self.moveCursor(Vec2i{ .a = 1, .b = 0 }, true),
                    'g' => self.moveCursorSpecial(CursorMove.StartOfBuffer, true),
                    'G' => self.moveCursorSpecial(CursorMove.EndOfBuffer, true),
                    // start inserting
                    'i' => self.setInputMode(.Insert),
                    'I' => {
                        self.moveCursorSpecial(CursorMove.StartOfLine, true);
                        self.setInputMode(.Insert);
                    },
                    'a' => {
                        self.moveCursor(Vec2i{ .a = 1, .b = 0 }, true);
                        self.setInputMode(.Insert);
                    },
                    'A' => {
                        self.moveCursorSpecial(CursorMove.EndOfLine, true);
                        self.setInputMode(.Insert);
                    },
                    'O' => {
                        self.moveCursorSpecial(CursorMove.StartOfLine, true);
                        self.newLine();
                        self.moveCursorSpecial(CursorMove.PreviousLine, true);
                        self.moveCursorSpecial(CursorMove.RespectPreviousLineIndent, true);
                        self.moveCursorSpecial(CursorMove.EndOfLine, true);
                        self.setInputMode(.Insert);
                    },
                    'o' => {
                        self.moveCursorSpecial(CursorMove.EndOfLine, true);
                        self.newLine();
                        self.setInputMode(.Insert);
                    },
                    // copy & paste
                    'v' => {
                        self.startSelection(self.cursor.pos, .KeyboardSelection);
                    },
                    'y' => {
                        if (self.selection.state == .KeyboardSelection or self.selection.state == .Active) {
                            if (self.buildSelectedText()) |selected_text| {
                                if (selected_text.size() > 0) {
                                    _ = c.SDL_SetClipboardText(@ptrCast([*:0]const u8, selected_text.data.items));
                                }
                                selected_text.deinit();
                            } else |err| {
                                std.log.err("WidgetTextEdit.onTextInput: can't get selected text: {}", .{err});
                            }
                            self.stopSelection(.Inactive);
                        }
                    },
                    'p' => {
                        self.paste() catch |err| {
                            std.log.err("WidgetTextEdit.onTextInput: can't paste: {}", .{err});
                        };
                    },
                    // others
                    'd' => {
                        if (self.editor.deleteLine(@intCast(usize, self.cursor.pos.b))) {
                            if (self.cursor.pos.b > 0 and self.cursor.pos.b >= self.editor.buffer.lines.items.len) {
                                self.moveCursor(Vec2i{ .a = 0, .b = -1 }, true);
                            }
                            self.validateCursorPosition(true);
                        } else |err| {
                            std.log.err("WidgetTextEdit.onTextInput: can't delete line: {}", .{err});
                        }
                    },
                    // TODO(remy): selection support
                    'x' => {
                        // edge-case: last char of the line
                        if (self.editor.buffer.getLine(self.cursor.pos.b)) |line| {
                            if (line.size() > 0 and
                                ((self.cursor.pos.a == line.size() - 1 and self.cursor.pos.b < self.editor.buffer.lines.items.len - 1) // normal line
                                or // normal line
                                (self.cursor.pos.a == line.size() and self.cursor.pos.b == self.editor.buffer.lines.items.len - 1)) // very last line
                            ) {
                                // special case, we don't want to do delete anything
                                return true;
                            }
                        } else |err| {
                            std.log.err("WidgetTextEdit.onTextInput: can't get line while executing 'x' input: {}", .{err});
                        }
                        self.editor.deleteUtf8Char(self.cursor.pos, false) catch |err| {
                            std.log.err("WidgetTextEdit.onTextInput: can't delete utf8 char while executing 'x' input: {}", .{err});
                        };
                    },
                    'u' => {
                        self.undo();
                    },
                    'r' => self.input_mode = .Replace, // TODO(remy): finish
                    else => return false,
                }
            },
        }
        return true;
    }

    // TODO(remy): support untabbing selection
    // TODO(remy): automatically respect previous indent on empty lines
    pub fn onTab(self: *WidgetTextEdit, shift: bool) void {
        switch (self.input_mode) {
            .Insert => {
                var i: usize = 0;
                while (i < tab_spaces) : (i += 1) {
                    self.editor.insertUtf8Text(self.cursor.pos, string_space) catch {}; // TODO(remy): grab the error
                }
                self.moveCursor(Vec2i{ .a = 4, .b = 0 }, true);
            },
            else => {
                var i: usize = 0;
                var pos = Vec2u{ .a = 0, .b = self.cursor.pos.b };
                if (shift) {
                    if (self.editor.buffer.getLine(pos.b)) |line| {
                        while (i < tab_spaces) : (i += 1) {
                            if (line.size() > 0 and line.data.items[0] == char_space) {
                                self.editor.deleteUtf8Char(pos, false) catch {}; // TODO(remy): grab the error
                            }
                        }
                    } else |_| {} // TODO(remy): grab the error
                } else {
                    while (i < tab_spaces) : (i += 1) {
                        self.editor.insertUtf8Text(pos, string_space) catch {}; // TODO(remy): grab the error
                    }
                }
            },
        }

        // make sure the cursor is on a viable position.
        self.validateCursorPosition(true);
    }

    // FIXME(remy): this should move the viewport but not moving the
    // the cursor.
    pub fn onMouseWheel(self: *WidgetTextEdit, move: Vec2i) void {
        var scroll_move = @divTrunc(@intCast(i64, self.viewport.lines.b) - @intCast(i64, self.viewport.lines.a), 4);
        if (scroll_move < 0) {
            scroll_move = 4;
        }

        if (move.b < 0) {
            self.moveViewport(Vec2i{ .a = 0, .b = scroll_move });
        } else if (move.b > 0) {
            self.moveViewport(Vec2i{ .a = 0, .b = -scroll_move });
        }
        if (move.a < 0) {
            self.moveViewport(Vec2i{ .a = -scroll_move, .b = 0 });
        } else if (move.a > 0) {
            self.moveViewport(Vec2i{ .a = scroll_move, .b = 0 });
        }
    }

    // TODO(remy): unit test
    pub fn onMouseMove(self: *WidgetTextEdit, mouse_window_pos: Vec2u, draw_pos: Vec2u) void {
        // ignore out of the editor click
        if (mouse_window_pos.a < draw_pos.a or mouse_window_pos.b < draw_pos.b) {
            return;
        }

        // ignore movements when not selecting text.
        if (self.selection.state != .MouseSelection) {
            return;
        }

        var cursor_pos = self.cursorPosFromWindowPos(mouse_window_pos, draw_pos);

        if (cursor_pos.b < 0) {
            cursor_pos.b = 0;
        } else if (cursor_pos.b >= self.editor.buffer.lines.items.len) {
            cursor_pos.b = self.editor.buffer.lines.items.len - 1;
        }

        var line = self.editor.buffer.getLine(cursor_pos.b) catch |err| {
            std.log.err("WindowText.onMouseMove: can't get current line {d}: {}", .{ cursor_pos.b, err });
            return;
        };
        var utf8size = line.utf8size() catch |err| {
            std.log.err("WindowText.onMouseMove: can't get current line utf8size {d}: {}", .{ cursor_pos.b, err });
            return;
        };

        if (cursor_pos.a > utf8size) {
            cursor_pos.a = utf8size;
        }

        self.updateSelection(cursor_pos);
        self.setCursorPos(cursor_pos, true);
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn onReturn(self: *WidgetTextEdit) void {
        switch (self.input_mode) {
            .Insert => self.newLine(),
            else => self.moveCursor(Vec2i{ .a = 0, .b = 1 }, true),
        }
    }

    // TODO(remy):
    // TODO(remy): comment
    /// returns true if the event has been absorbed by the WidgetTextEdit.
    pub fn onEscape(self: *WidgetTextEdit) bool {
        // stop selection mode
        self.stopSelection(.Inactive);

        // checks if we have to enter command mode
        switch (self.input_mode) {
            .Insert, .Replace => {
                // enter command mod
                self.input_mode = InputMode.Command;
                return true;
            },
            else => return false,
        }
    }

    // TODO(remy):
    // TODO(remy): comment
    pub fn onBackspace(self: *WidgetTextEdit) void {
        switch (self.input_mode) {
            .Insert => {
                self.editor.deleteUtf8Char(self.cursor.pos, true) catch |err| {
                    std.log.err("WidgetTextEdit.onBackspace: {}", .{err});
                };
                self.moveCursor(Vec2i{ .a = -1, .b = 0 }, true);
            },
            else => {},
        }
    }

    // TODO(remy): unit test
    pub fn onMouseStartSelection(self: *WidgetTextEdit, mouse_window_pos: Vec2u, draw_pos: Vec2u) void {
        if (mouse_window_pos.a < draw_pos.a or mouse_window_pos.b < draw_pos.b) {
            return;
        }

        // move the mouse on the click
        var cursor_pos = self.cursorPosFromWindowPos(mouse_window_pos, draw_pos);
        self.setCursorPos(cursor_pos, false);
        self.validateCursorPosition(true);

        // use the position (which may have been corrected) as the selection start position
        self.startSelection(self.cursor.pos, .MouseSelection);
    }

    // TODO(remy): unit test
    pub fn onMouseStopSelection(self: *WidgetTextEdit, mouse_window_pos: Vec2u, draw_pos: Vec2u) void {
        if (mouse_window_pos.a < draw_pos.a or mouse_window_pos.b < draw_pos.b) {
            return;
        }

        // do not completely stop the selection, the user may want to finish it using the keyboard.
        self.stopSelection(.KeyboardSelection);
    }

    // Text edition methods
    // -------------------

    // TODO(remy): comment
    // TODO(remy): unit test
    /// buildSelectedText always returns a string ending with a \0.
    pub fn buildSelectedText(self: WidgetTextEdit) !U8Slice {
        var rv = U8Slice.initEmpty(self.allocator);
        errdefer rv.deinit();

        if (self.selection.state == .Inactive) {
            return rv;
        }

        var i: usize = self.selection.start.b;
        while (i <= self.selection.stop.b) : (i += 1) {
            var line = try self.editor.buffer.getLine(i);
            if (i == self.selection.start.b and i != self.selection.stop.b) {
                // selection starting somewhere in the first line
                var start_pos = try line.utf8pos(self.selection.start.a);
                try rv.appendConst(line.bytes()[start_pos..line.size()]);
            } else if (i == self.selection.start.b and i == self.selection.stop.b) {
                // selection starting somewhere in the first line and ending in the same
                var start_pos = try line.utf8pos(self.selection.start.a);
                var end_pos = try line.utf8pos(self.selection.stop.a);
                try rv.appendConst(line.bytes()[start_pos..end_pos]);
            } else if (i != self.selection.start.b and i == self.selection.stop.b) {
                var end_pos = try line.utf8pos(self.selection.stop.a);
                try rv.appendConst(line.bytes()[0..end_pos]);
            } else {
                try rv.appendConst(line.bytes());
            }
        }

        try rv.data.append(0);

        return rv;
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    // TODO(remy): implement smooth movement
    pub fn moveViewport(self: *WidgetTextEdit, move: Vec2i) void {
        var cols_a: i64 = 0;
        var cols_b: i64 = 0;
        var lines_a: i64 = 0;
        var lines_b: i64 = 0;

        cols_a = @intCast(i64, self.viewport.columns.a) + move.a;
        cols_b = @intCast(i64, self.viewport.columns.b) + move.a;

        // lines

        lines_a = @intCast(i64, self.viewport.lines.a) + move.b;
        lines_b = @intCast(i64, self.viewport.lines.b) + move.b;

        if (lines_a < 0) {
            self.viewport.lines.a = 0;
            self.viewport.lines.b = self.visible_cols_and_lines.b;
        } else if (lines_a > self.editor.buffer.lines.items.len) {
            return;
        } else {
            self.viewport.lines.a = @intCast(usize, lines_a);
            self.viewport.lines.b = @intCast(usize, lines_b);
        }

        // +5 here to allow some space on the window right border and the text
        const longest_visible_line = self.editor.buffer.longestLine(self.viewport.lines.a, self.viewport.lines.b) + 5;

        // columns

        if (cols_a < 0) {
            self.viewport.columns.a = 0;
            self.viewport.columns.b = self.visible_cols_and_lines.a;
        } else if (cols_b > longest_visible_line) {
            self.viewport.columns.a = @intCast(usize, @max(0, @intCast(i64, longest_visible_line) - @intCast(i64, self.visible_cols_and_lines.a)));
            self.viewport.columns.b = longest_visible_line;
        } else {
            self.viewport.columns.a = @intCast(usize, cols_a);
            self.viewport.columns.b = @intCast(usize, cols_b);
        }

        if (self.viewport.columns.b > longest_visible_line) {
            self.viewport.columns.a = @intCast(usize, @max(0, @intCast(i64, longest_visible_line) - @intCast(i64, self.visible_cols_and_lines.a)));
            self.viewport.columns.b = @max(longest_visible_line, self.visible_cols_and_lines.a);
        } else {
            self.viewport.columns.b = self.viewport.columns.a + self.visible_cols_and_lines.a;
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    /// If you want to make sure the cursor is on a valid position, consider
    /// using `validateCursorPosition`.
    pub fn moveCursor(self: *WidgetTextEdit, move: Vec2i, scroll: bool) void {
        var cursor_pos = Vec2utoi(self.cursor.pos);
        var line: *U8Slice = undefined;
        var utf8size: usize = 0;

        if (self.editor.buffer.getLine(self.cursor.pos.b)) |l| {
            line = l;
        } else |err| {
            // still, report the error
            std.log.err("WidgetTextEdit.moveCursor: can't get line {d}: {}", .{ cursor_pos.b, err });
            return;
        }

        if (line.utf8size()) |size| {
            utf8size = size;
        } else |err| {
            std.log.err("WidgetTextEdit.moveCursor: can't get line {d} utf8size: {}", .{ cursor_pos.b, err });
            return;
        }

        // y movement
        if (cursor_pos.b + move.b <= 0) {
            self.cursor.pos.b = 0;
        } else {
            self.cursor.pos.b = @intCast(usize, cursor_pos.b + move.b);
        }

        // x movement
        if (cursor_pos.a + move.a <= 0) {
            self.cursor.pos.a = 0;
        } else {
            self.cursor.pos.a = @intCast(usize, cursor_pos.a + move.a);
        }

        self.validateCursorPosition(scroll);
        if (self.selection.state == .KeyboardSelection) {
            self.updateSelection(self.cursor.pos);
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn validateCursorPosition(self: *WidgetTextEdit, scroll: bool) void {
        if (self.cursor.pos.b >= self.editor.buffer.lines.items.len and self.editor.buffer.lines.items.len > 0) {
            self.cursor.pos.b = self.editor.buffer.lines.items.len - 1;
        }

        if (self.editor.buffer.lines.items[self.cursor.pos.b].utf8size()) |utf8size| {
            if (utf8size == 0) {
                self.cursor.pos.a = 0;
            } else {
                if (self.cursor.pos.a >= utf8size) {
                    // there is a edge case: on the last line, we're OK going one
                    // char out, in order to be able to insert new things there.
                    if (self.cursor.pos.b < @intCast(i64, self.editor.buffer.lines.items.len) - 1) {
                        self.cursor.pos.a = utf8size - 1;
                    } else {
                        self.cursor.pos.a = utf8size;
                    }
                }
            }
        } else |err| {
            std.log.err("WidgetTextEdit.moveCursor: can't get utf8size of the line {d}: {}", .{ self.cursor.pos.b, err });
        }

        if (scroll) {
            self.scrollToCursor();
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn moveCursorSpecial(self: *WidgetTextEdit, move: CursorMove, scroll: bool) void {
        var scrolled = false;
        switch (move) {
            .EndOfLine => {
                if (self.editor.buffer.getLine(self.cursor.pos.b)) |l| {
                    if (l.utf8size()) |utf8size| {
                        if (l.bytes()[l.bytes().len - 1] == '\n') {
                            self.cursor.pos.a = utf8size - 1;
                        } else {
                            self.cursor.pos.a = utf8size;
                        }
                    } else |err| {
                        std.log.err("WidgetTextEdit.moveCursorSpecial.EndOfLine: can't get utf8size of the line: {}", .{err});
                    }
                } else |err| {
                    std.log.err("WidgetTextEdit.moveCursorSpecial.EndOfLine: {}", .{err});
                }
            },
            .StartOfLine => {
                self.cursor.pos.a = 0;
            },
            .EndOfWord => {
                std.log.debug("moveCursorSpecial.StartOfWord: implement me!", .{}); // TODO(remy): implement
            },
            .StartOfWord => {
                std.log.debug("moveCursorSpecial.StartOfWord: implement me!", .{}); // TODO(remy): implement
            },
            .StartOfBuffer => {
                self.cursor.pos.a = 0;
                self.cursor.pos.b = 0;
            },
            .EndOfBuffer => {
                self.cursor.pos.b = self.editor.buffer.lines.items.len - 1;
                self.moveCursorSpecial(CursorMove.EndOfLine, scroll);
                scrolled = scroll;
            },
            .NextSpace => {
                std.log.debug("moveCursorSpecial.NextSpace: implement me!", .{}); // TODO(remy): implement
            },
            .PreviousSpace => {
                std.log.debug("moveCursorSpecial.PreviousSpace: implement me!", .{});
            },
            .NextLine => {
                self.moveCursor(Vec2i{ .a = 0, .b = 1 }, scroll);
                scrolled = scroll;
            },
            .PreviousLine => {
                self.moveCursor(Vec2i{ .a = 0, .b = -1 }, scroll);
                scrolled = scroll;
            },
            // TODO(remy): unit test
            .AfterIndentation => {
                if (self.editor.buffer.getLine(self.cursor.pos.b)) |l| {
                    if (l.size() == 0) {
                        return;
                    }
                    var i: usize = 0;
                    while (l.bytes()[i] == char_space) : (i += 1) {}
                    self.moveCursor(Vec2i{ .a = @intCast(i64, i), .b = 0 }, true);
                } else |_| {} // TODO(remy): do something with the error
            },
            // TODO(remy): unit test
            .RespectPreviousLineIndent => {
                if (self.cursor.pos.b == 0) {
                    return;
                }
                if (self.editor.buffer.getLine(self.cursor.pos.b - 1)) |l| {
                    if (l.size() == 0) {
                        return;
                    }
                    var i: usize = 0;
                    var start_line_pos = Vec2u{ .a = 0, .b = self.cursor.pos.b };
                    while (l.bytes()[i] == char_space) : (i += 1) {
                        self.editor.insertUtf8Text(start_line_pos, string_space) catch {}; // TODO(remy): do something with the error
                    }
                } else |_| {} // TODO(remy): do something with the error
            },
        }

        if (scroll and !scrolled) {
            self.scrollToCursor();
        }

        // make sure the cursor is on a valid position
        self.validateCursorPosition(scroll and !scrolled);
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn newLine(self: *WidgetTextEdit) void {
        self.editor.newLine(self.cursor.pos, false) catch |err| {
            std.log.err("WidgetTextEdit.newLine: {}", .{err});
            return;
        };
        self.moveCursorSpecial(CursorMove.NextLine, true);
        self.moveCursorSpecial(CursorMove.StartOfLine, true);
        self.moveCursorSpecial(CursorMove.RespectPreviousLineIndent, true);
        self.moveCursorSpecial(CursorMove.AfterIndentation, true);
    }

    // Others
    // ------

    // TODO(remy): comment
    pub fn setInputMode(self: *WidgetTextEdit, input_mode: InputMode) void {
        if (input_mode == .Insert) {
            // stop any selection
            self.stopSelection(.Inactive);

            // there is a edge case when entering insert mode while on the very last
            // char of the document.
            if (self.editor.buffer.getLine(self.cursor.pos.b)) |line| {
                if (line.utf8size()) |utf8size| {
                    if (self.cursor.pos.a == utf8size) {}
                } else |_| {}
            } else |_| {}
        }
        self.input_mode = input_mode;
    }

    /// goToLine goes to the given line.
    /// First line starts at 1.
    pub fn goToLine(self: *WidgetTextEdit, line_number: usize, scroll: bool) void {
        var pos = Vec2u{ .a = self.cursor.pos.a, .b = line_number };

        if (pos.b > 0) {
            pos.b -= 1;
        } else {
            pos.b = 0;
        }

        self.setCursorPos(pos, false); // no need to scroll here, we'll do it next function call
        self.validateCursorPosition(scroll);
    }

    // TODO(remy): comment
    pub fn undo(self: *WidgetTextEdit) void {
        if (self.editor.undo()) |pos| {
            self.setCursorPos(pos, true);
        } else |err| {
            if (err != EditorError.NothingToUndo) {
                std.log.err("WidgetTextEdit.undo: can't undo: {}", .{err});
            }
        }
    }
};

test "widget_text_edit moveCursor" {
    const allocator = std.testing.allocator;
    var app: *App = undefined;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var widget = WidgetTextEdit.initWithBuffer(allocator, app, buffer, Vec2u{ .a = 50, .b = 100 });
    widget.cursor.pos = Vec2u{ .a = 0, .b = 0 };

    // top of the file, moving up shouldn't do anything
    widget.moveCursor(Vec2i{ .a = 0, .b = -1 }, true);
    try expect(widget.cursor.pos.a == 0);
    try expect(widget.cursor.pos.b == 0);
    // move down
    widget.moveCursor(Vec2i{ .a = 0, .b = 1 }, true);
    try expect(widget.cursor.pos.a == 0);
    try expect(widget.cursor.pos.b == 1);
    // big move down, should reach the last line of the file
    widget.moveCursor(Vec2i{ .a = 0, .b = 15 }, true);
    try expect(widget.cursor.pos.a == 0);
    try expect(widget.cursor.pos.b == buffer.lines.items.len - 1);
    // big move up, should reach the top line
    widget.moveCursor(Vec2i{ .a = 0, .b = -15 }, true);
    try expect(widget.cursor.pos.a == 0);
    try expect(widget.cursor.pos.b == 0);
    // move right
    widget.moveCursor(Vec2i{ .a = 1, .b = 0 }, true);
    try expect(widget.cursor.pos.a == 1);
    try expect(widget.cursor.pos.b == 0);
    // big move right, should reach the end of the line
    widget.moveCursor(Vec2i{ .a = 100, .b = 0 }, true);
    try expect(widget.cursor.pos.a == buffer.lines.items[0].size() - 1);
    try expect(widget.cursor.pos.b == 0);
    // move left
    widget.moveCursor(Vec2i{ .a = -1, .b = 0 }, true);
    try expect(widget.cursor.pos.a == buffer.lines.items[0].size() - 2);
    try expect(widget.cursor.pos.b == 0);
    // big move left, should reach the start of the line
    widget.moveCursor(Vec2i{ .a = -100, .b = 0 }, true);
    try expect(widget.cursor.pos.a == 0);
    try expect(widget.cursor.pos.b == 0);
    // big move right and up, should reach the last line and its end
    widget.moveCursor(Vec2i{ .a = 100, .b = 100 }, true);
    // var size = buffer.lines.items[0].size();
    // try expect(widget.cursor.pos.a == buffer.lines.items[0].size() - 1); // FIXME(remy): broken unit test
    // try expect(widget.cursor.pos.b == buffer.lines.items.len - 1);

    widget.deinit();
}

test "widget_text_edit moveCursorSpecial" {
    const allocator = std.testing.allocator;
    var app: *App = undefined;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var widget = WidgetTextEdit.initWithBuffer(allocator, app, buffer, Vec2u{ .a = 50, .b = 100 });
    widget.cursor.pos = Vec2u{ .a = 0, .b = 0 };

    widget.moveCursorSpecial(CursorMove.EndOfLine, true);
    try expect(widget.cursor.pos.a == 11);
    try expect(widget.cursor.pos.b == 0);
    widget.moveCursorSpecial(CursorMove.StartOfLine, true);
    try expect(widget.cursor.pos.a == 0);
    try expect(widget.cursor.pos.b == 0);
    widget.moveCursorSpecial(CursorMove.StartOfBuffer, true);
    try expect(widget.cursor.pos.a == 0);
    try expect(widget.cursor.pos.b == 0);
    widget.moveCursorSpecial(CursorMove.EndOfBuffer, true);
    try expect(widget.cursor.pos.b == 2);
    // this one is the very end of the document, should not go "outside" of
    // the buffer of one extra char.
    try expect(widget.cursor.pos.a == 11);
    try expect(widget.cursor.pos.b == 2);

    widget.deinit();
}

test "widget_text_edit init deinit" {
    const allocator = std.testing.allocator;
    var app: *App = undefined;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    var widget = WidgetTextEdit.initWithBuffer(allocator, app, buffer, Vec2u{ .a = 50, .b = 100 });
    widget.deinit();
}
