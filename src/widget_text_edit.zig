const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const Buffer = @import("buffer.zig").Buffer;
const Colors = @import("colors.zig");
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
const Vec4u = @import("vec.zig").Vec4u;

const char_space = @import("u8slice.zig").char_space;
const char_tab = @import("u8slice.zig").char_tab;
const char_linereturn = @import("u8slice.zig").char_linereturn;
const string_space = @import("u8slice.zig").string_space;

// TODO(remy): where should we define this?
// TODO(remy): comment
// TODO(remy): comment
pub const char_offset_before_move = 5;
// TODO(remy): comment
pub const tab_spaces = 4;

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
    pub fn render(
        _: Cursor,
        sdl_renderer: *c.SDL_Renderer,
        input_mode: InputMode,
        scaler: Scaler,
        draw_pos: Vec2u,
        one_char_size: Vec2u,
    ) void {
        switch (input_mode) {
            .Insert => {
                Draw.fillRect(
                    sdl_renderer,
                    scaler,
                    Vec2u{
                        .a = draw_pos.a,
                        .b = draw_pos.b,
                    },
                    Vec2u{ .a = 2, .b = one_char_size.b },
                    Colors.white,
                );
            },
            else => {
                Draw.fillRect(
                    sdl_renderer,
                    scaler,
                    Vec2u{
                        .a = draw_pos.a,
                        .b = draw_pos.b,
                    },
                    Vec2u{ .a = one_char_size.a, .b = one_char_size.b },
                    Colors.white,
                );
            },
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    fn posFromWindowPos(_: Cursor, text_edit: *WidgetTextEdit, click_window_pos: Vec2u, draw_pos: Vec2u) Vec2u {
        var rv = Vec2u{ .a = 0, .b = 0 };

        // position in char in window
        // --

        var in_editor = Vec2u{
            .a = @intCast(usize, @max(@intCast(i64, click_window_pos.a - draw_pos.a) - @intCast(i64, text_edit.line_numbers_offset), 0)) / text_edit.one_char_size.a,
            .b = (click_window_pos.b - draw_pos.b) / text_edit.one_char_size.b,
        };

        // line
        // --

        rv.b = in_editor.b;
        rv.b += text_edit.viewport.lines.a;

        if (rv.b < 0) {
            rv.b = 0;
        } else if (rv.b >= text_edit.editor.buffer.lines.items.len) {
            rv.b = text_edit.editor.buffer.lines.items.len - 1;
            var last_line = text_edit.editor.buffer.getLine(text_edit.editor.buffer.lines.items.len - 1) catch |err| {
                std.log.err("Cursor.posFromWindowPos: can't get last line {d}: {}", .{ rv.b, err });
                return rv;
            };
            rv.a = last_line.size() - 1;
            return rv;
        }

        // column
        // --

        rv.a = text_edit.viewport.columns.a;

        var line = text_edit.editor.buffer.getLine(rv.b) catch |err| {
            std.log.err("Cursor.posFromWindowPos: can't get current line {d}: {}", .{ rv.b, err });
            return rv;
        };

        var utf8size = line.utf8size() catch |err| {
            std.log.err("Cursor.posFromWindowPos: can't get current line utf8size {d}: {}", .{ rv.b, err });
            return rv;
        };

        if (rv.a > utf8size) {
            rv.a = utf8size;
            return rv;
        }

        if (in_editor.a == 0) {
            rv.a = text_edit.viewport.columns.a;
            return rv;
        }

        var buff_idx: usize = 0;
        var tabs_idx: usize = 0;
        var move_done: usize = 0;
        var bytes = line.bytes();

        while (move_done < text_edit.viewport.columns.b and buff_idx < bytes.len) {
            if (bytes[buff_idx] == char_tab and tabs_idx == 0) {
                // it is a tab
                tabs_idx = 4;
            }
            if (tabs_idx > 0) {
                tabs_idx -= 1;
            }
            if (tabs_idx == 0) {
                var glyph_bytes_size = line.utf8glyphSize(buff_idx);
                buff_idx += glyph_bytes_size;
            }

            move_done += 1;
            if (move_done >= text_edit.viewport.columns.a + in_editor.a) {
                rv.a = move_done;
                break;
            }
        }

        return rv;
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
    line_numbers_offset: usize, // when rendering the line number, it creates a left offset
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
            .line_numbers_offset = 0,
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
            .a = (widget_size.a) / @floatToInt(usize, @intToFloat(f32, one_char_size.a)),
            .b = ((widget_size.b) / @floatToInt(usize, @intToFloat(f32, one_char_size.b))) - 1, // FIXME(remy): this -1 is based on nothing
        };
        self.computeViewport();

        var pos = draw_pos;

        // render line numbers
        // it creates a left offset

        var left_offset: usize = 0;

        if (self.draw_line_numbers) {
            left_offset = self.renderLineNumbers(sdl_renderer, font, scaler, pos, widget_size, one_char_size);
            pos.a += left_offset;
        }

        // render the lines
        // it also adds a left offset (a small blank)

        left_offset = self.renderLinesAndSelection(font, scaler, pos, one_char_size);
        pos.a += left_offset;

        self.line_numbers_offset = pos.a;
    }

    /// Returns x offset introduced by drawing the lines numbers
    fn renderLineNumbers(self: WidgetTextEdit, sdl_renderer: *c.SDL_Renderer, font: Font, scaler: Scaler, draw_pos: Vec2u, widget_size: Vec2u, one_char_size: Vec2u) usize {
        var text_pos_x: usize = one_char_size.a;

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

        // render the separation line

        Draw.line(
            sdl_renderer,
            scaler,
            Vec2u{ .a = draw_pos.a + width, .b = draw_pos.b },
            Vec2u{ .a = draw_pos.a + width, .b = widget_size.b - draw_pos.b },
            Vec4u{ .a = 70, .b = 70, .c = 70, .d = 255 },
        );

        // render the line numbers

        while (i < self.viewport.lines.b and i < self.editor.buffer.lines.items.len) : (i += 1) {
            _ = std.fmt.bufPrintZ(cbuff, "{d}", .{i + 1}) catch |err| {
                std.log.err("WidgetTextEdit.renderLineNumbers: can't render line number {}: {}", .{ i, err });
                return 0;
            };

            var text_color = Colors.gray;
            if (i == self.cursor.pos.b) {
                text_color = Colors.white;
            }

            Draw.text(
                font,
                scaler,
                Vec2u{ .a = text_pos_x, .b = y_offset },
                text_color,
                cbuff,
            );

            if (i == self.cursor.pos.b) {
                Draw.fillRect(
                    sdl_renderer,
                    scaler,
                    Vec2u{ .a = draw_pos.a, .b = y_offset },
                    Vec2u{ .a = draw_pos.a + width, .b = self.one_char_size.b },
                    Vec4u{ .a = 220, .b = 220, .c = 220, .d = 20 },
                );
            }

            y_offset += self.one_char_size.b;
        }

        return width;
    }

    // TODO(remy): remove
    fn glyphColor(_: WidgetTextEdit, str: []const u8) Vec4u {
        if (str.len == 0) {
            return Colors.light_gray;
        }

        if (str[0] == '(' or str[0] == ')' or
            str[0] == '[' or str[0] == ']' or
            str[0] == '{' or str[0] == '}')
        {
            return Vec4u{ .a = 46, .b = 126, .c = 184, .d = 255 };
        }

        return Colors.light_gray;
    }

    fn renderLinesAndSelection(self: WidgetTextEdit, font: Font, scaler: Scaler, draw_pos: Vec2u, one_char_size: Vec2u) usize {
        var i: usize = self.viewport.lines.a;
        var y_offset: usize = 0;
        var left_blank_offset: usize = 5;

        while (i < self.viewport.lines.b) : (i += 1) {
            if (self.editor.buffer.getLine(i)) |line| {
                // empty line, just jump a line

                if (line.size() == 0) {
                    y_offset += self.one_char_size.b;
                    continue;
                }

                // we always have to render every line from the start: since they may contain a \t
                // we will have to take care of the fact that a \t use multiple spaces.

                var buff_idx: usize = 0;
                var tab_idx: usize = 0;
                var move_done: usize = 0;
                var offset: usize = 0; // offset in char, relative to the left of the widget (i.e. right of the line numbers if any)
                var bytes = line.bytes();

                while (buff_idx < line.size() and offset < self.viewport.columns.b) {
                    var glyph_bytes_size: usize = line.utf8glyphSize(buff_idx);

                    if (bytes[buff_idx] == char_tab and tab_idx == 0) {
                        tab_idx = tab_spaces;
                    }

                    // render the glyph only if not rendering a tab and we "moved" enough
                    // to be in the viewport
                    if (move_done >= self.viewport.columns.a) {

                        // if we're not currently rendering a tab
                        // we have to draw a glyph

                        if (tab_idx == 0) {
                            var color = self.glyphColor(bytes[buff_idx..]);
                            _ = Draw.glyph(
                                font,
                                scaler,
                                Vec2u{
                                    .a = draw_pos.a + (offset * one_char_size.a) + left_blank_offset,
                                    .b = draw_pos.b + y_offset,
                                },
                                color,
                                bytes[buff_idx..],
                            );
                        }

                        // draw the selection rectangle if necessary

                        if (self.isSelected(Vec2u{ .a = move_done, .b = i })) {
                            Draw.fillRect(
                                font.sdl_renderer,
                                scaler,
                                Vec2u{
                                    .a = draw_pos.a + (offset * one_char_size.a) + left_blank_offset,
                                    .b = draw_pos.b + y_offset,
                                },
                                one_char_size,
                                Vec4u{ .a = 175, .b = 175, .c = 175, .d = 100 },
                            );
                        }

                        // draw the cursor if necessary

                        if (self.cursor.pos.a == move_done and (tab_idx == 4 or tab_idx == 0) and self.cursor.pos.b == i) {
                            self.cursor.render(
                                font.sdl_renderer,
                                self.input_mode,
                                scaler,
                                Vec2u{
                                    .a = draw_pos.a + (offset * one_char_size.a) + left_blank_offset,
                                    .b = draw_pos.b + y_offset,
                                },
                                one_char_size,
                            );
                        }
                    }

                    // move in the actual buffer only if we're not in a tab
                    if (tab_idx == 0) {
                        buff_idx += glyph_bytes_size;
                    } else {
                        // we are currently drawing a tab
                        tab_idx -= 1;
                        if (tab_idx == 0) { // are we done drawing this tab? time to move forward in the idx
                            buff_idx += glyph_bytes_size;
                        }
                    }

                    // move right only where we are currently drawing in the viewport
                    // otherwise, it's just offscreen movement, we don't have anything to draw
                    if (move_done >= self.viewport.columns.a) {
                        offset += 1;
                    }
                    move_done += 1;
                }

                y_offset += self.one_char_size.b;
            } else |_| {
                // TODO(remy): do something with the error
            }
        }

        return left_blank_offset;
    }

    // TODO(remy): unit test
    fn isSelected(self: WidgetTextEdit, glyph: Vec2u) bool {
        if (self.selection.state == .Inactive) {
            return false;
        }

        if (glyph.b < self.selection.start.b or glyph.b > self.selection.stop.b) {
            return false;
        }

        // one the starting line

        if (glyph.b == self.selection.start.b and glyph.b != self.selection.stop.b) {
            if (glyph.a >= self.selection.start.a) {
                return true;
            }
            return false;
        }

        // one the ending line

        if (glyph.b == self.selection.stop.b and glyph.b != self.selection.start.b) {
            if (glyph.a <= self.selection.stop.a) {
                return true;
            }
            return false;
        }

        // starting and ending on this line
        if (self.selection.start.b == self.selection.stop.b and glyph.b == self.selection.start.b and
            glyph.a >= self.selection.start.a and glyph.a <= self.selection.stop.a)
        {
            return true;
        }

        if (glyph.b >= self.selection.start.b and glyph.b < self.selection.stop.b) {
            return true;
        }

        return false;
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

        var cursor_pos = self.cursor.posFromWindowPos(self, mouse_window_pos, draw_pos);

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
        var cursor_pos = self.cursor.posFromWindowPos(self, mouse_window_pos, draw_pos);
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
                        if (l.bytes()[l.bytes().len - 1] == char_linereturn) {
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
                    while (l.bytes()[i] == char_space or l.bytes()[i] == char_tab) : (i += 1) {}
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
                    while (l.bytes()[i] == char_space or l.bytes()[i] == char_tab) : (i += 1) {
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
