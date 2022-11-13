const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const Buffer = @import("buffer.zig").Buffer;
const Editor = @import("editor.zig").Editor;
const EditorError = @import("editor.zig").EditorError;
const ImVec2 = @import("vec.zig").ImVec2;
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
pub const page_move = 8;
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

    /// `render` renders the cursor in the `WidgetText`.
    // TODO(remy): consider redrawing the character which is under the cursor in a reverse color to see it above the cursor
    /// `line_offset_in_buffer` contains the first visible line (of the buffer) in the current window. With this + the position
    /// of the cursor in the buffer, we can compute where to relatively position the cursor in the window in order to draw it.
    pub fn render(self: Cursor, draw_list: *c.ImDrawList, input_mode: InputMode, viewport: WidgetTextViewport, editor_drawing_offset: Vec2f, font_size: Vec2f) void {
        // TODO(remy): columns
        var col_offset_in_buffer = viewport.columns.a;
        var line_offset_in_buffer = viewport.lines.a;

        switch (input_mode) {
            .Insert => {
                var x1 = @intToFloat(f32, self.pos.a - col_offset_in_buffer) * font_size.a;
                var x2 = x1 + 2;
                var y1 = @intToFloat(f32, self.pos.b - line_offset_in_buffer) * font_size.b;
                var y2 = @intToFloat(f32, self.pos.b + 1 - line_offset_in_buffer) * (font_size.b);
                c.ImDrawList_AddRectFilled(
                    draw_list,
                    ImVec2(editor_drawing_offset.a + x1, editor_drawing_offset.b + y1),
                    ImVec2(editor_drawing_offset.a + x2, editor_drawing_offset.b + y2),
                    0xFFFFFFFF,
                    1.0,
                    0,
                );
            },
            else => {
                var x1 = @intToFloat(f32, self.pos.a - col_offset_in_buffer) * font_size.a;
                var x2 = @intToFloat(f32, self.pos.a - col_offset_in_buffer + 1) * font_size.a;
                var y1 = @intToFloat(f32, self.pos.b - line_offset_in_buffer) * font_size.b;
                var y2 = @intToFloat(f32, self.pos.b + 1 - line_offset_in_buffer) * (font_size.b);
                c.ImDrawList_AddRectFilled(
                    draw_list,
                    ImVec2(editor_drawing_offset.a + x1, editor_drawing_offset.b + y1),
                    ImVec2(editor_drawing_offset.a + x2, editor_drawing_offset.b + y2),
                    0xFFFFFFFF,
                    1.0,
                    0,
                );
            },
        }
    }
};

pub const WidgetTextViewport = struct {
    lines: Vec2u,
    columns: Vec2u,
};

pub const WidgetTextSelection = struct {
    initial: Vec2u,
    start: Vec2u,
    stop: Vec2u,
    active: bool,
    in_progress: bool,
};

// TODO(remy): comment
pub const WidgetText = struct {
    allocator: std.mem.Allocator,
    app: *App,
    cursor: Cursor, // TODO(remy): replace me with a custom (containing cursor mode)
    editor: Editor,
    input_mode: InputMode,
    // TODO(remy): comment
    viewport: WidgetTextViewport,
    selection: WidgetTextSelection,
    one_char_size: Vec2f, // refreshed before every frame

    // Constructors
    // ------------

    // TODO(remy): comment
    pub fn initWithBuffer(allocator: std.mem.Allocator, app: *App, buffer: Buffer, cols_and_lines: Vec2u) WidgetText {
        return WidgetText{
            .allocator = allocator,
            .app = app,
            .cursor = Cursor.init(),
            .editor = Editor.init(allocator, buffer),
            .input_mode = InputMode.Insert,
            .one_char_size = Vec2f{ .a = 0, .b = 0 },
            .viewport = WidgetTextViewport{
                .columns = Vec2u{ .a = 0, .b = cols_and_lines.a },
                .lines = Vec2u{ .a = 0, .b = cols_and_lines.b },
            },
            .selection = WidgetTextSelection{
                .start = Vec2u{ .a = 0, .b = 0 },
                .initial = Vec2u{ .a = 0, .b = 0 },
                .stop = Vec2u{ .a = 0, .b = 0 },
                .active = false,
                .in_progress = false,
            },
        };
    }

    pub fn deinit(self: *WidgetText) void {
        self.editor.deinit();
    }

    // Rendering methods
    // -----------------

    // TODO(remy): comment
    // TODO(remy): unit test (at least to validate that there is no leaks)
    pub fn render(self: *WidgetText, one_char_size: Vec2f, window_size: Vec2i, editor_drawing_offset: Vec2f) void {
        var draw_list = c.igGetWindowDrawList();
        self.one_char_size = one_char_size;
        self.renderSelection(draw_list, editor_drawing_offset);
        self.renderLines(draw_list, editor_drawing_offset);
        self.renderLineNumbers(draw_list, window_size, editor_drawing_offset);
        self.renderCursor(draw_list, editor_drawing_offset);
    }

    fn renderCursor(self: WidgetText, draw_list: *c.ImDrawList, editor_drawing_offset: Vec2f) void {
        // render the cursor only if it is visible
        if (self.isCursorVisible()) {
            self.cursor.render(draw_list, self.input_mode, self.viewport, editor_drawing_offset, Vec2f{ .a = self.one_char_size.a, .b = self.one_char_size.b });
        }
    }

    fn renderLineNumbers(self: WidgetText, draw_list: *c.ImDrawList, window_size: Vec2i, editor_drawing_offset: Vec2f) void {
        var carray: [128]u8 = std.mem.zeroes([128]u8);
        var cbuff = &carray;

        var i: usize = self.viewport.lines.a;
        var y_offset: f32 = editor_drawing_offset.b;

        c.ImDrawList_AddRectFilled(
            draw_list,
            ImVec2(0, editor_drawing_offset.b),
            ImVec2(editor_drawing_offset.a - 10, @intToFloat(f32, window_size.b)),
            0xFF1A1A1A,
            1.0,
            0,
        );

        while (i < self.viewport.lines.b and i < self.editor.buffer.lines.items.len) : (i += 1) {
            _ = std.fmt.bufPrintZ(cbuff, "{d}", .{i + 1}) catch |err| {
                std.log.err("WidgetText.renderLineNumbers: can't render line number {}: {}", .{ i, err });
                return;
            };

            var text_color: c_uint = 0xFF5A5A5A;

            if (i == self.cursor.pos.b) {
                c.ImDrawList_AddRectFilled(
                    draw_list,
                    ImVec2(0, y_offset),
                    ImVec2(editor_drawing_offset.a - 10, y_offset + self.one_char_size.b),
                    0xFF777777,
                    0.0,
                    0,
                );
                text_color = 0xFF000000;
            }

            c.ImDrawList_AddText_Vec2(
                draw_list,
                ImVec2(10, y_offset),
                text_color,
                cbuff,
                0,
            );

            y_offset += self.one_char_size.b;
        }
    }

    fn renderLines(self: WidgetText, draw_list: *c.ImDrawList, editor_drawing_offset: Vec2f) void {
        var i: usize = self.viewport.lines.a;
        var j: usize = self.viewport.columns.a;
        var y_offset: f32 = 0;

        var carray: [8192]u8 = std.mem.zeroes([8192]u8);
        var cbuff = &carray;

        while (i < self.viewport.lines.b) : (i += 1) {
            j = self.viewport.columns.a;
            if (self.editor.buffer.getLine(i)) |line| {
                var buff: *[]u8 = &line.data.items; // uses a pointer only to avoid a copy

                // empty line
                if (buff.len == 0 or (buff.len == 1 and buff.*[0] == '\n') or buff.len < self.viewport.columns.a) {
                    c.ImDrawList_AddText_Vec2(draw_list, ImVec2(editor_drawing_offset.a, editor_drawing_offset.b + y_offset), 0xFFC0C0C0, "", 0);
                    y_offset += self.one_char_size.b;
                    continue;
                }

                // grab only what's visible in the viewport in the temporary buffer
                while (j < self.viewport.columns.b and j < buff.len) : (j += 1) {
                    cbuff[j - self.viewport.columns.a] = buff.*[j];
                }
                cbuff[j - self.viewport.columns.a] = 0;

                c.ImDrawList_AddText_Vec2(draw_list, ImVec2(editor_drawing_offset.a, editor_drawing_offset.b + y_offset), 0xFFC0C0C0, @ptrCast([*:0]const u8, cbuff), 0);
                y_offset += self.one_char_size.b;

                // std.log.debug("self.buffer.data.items[{d}..{d}] (len: {d}) data: {s}", .{ @intCast(usize, pos.a), @intCast(usize, pos.b), self.buffer.data.items.len, @ptrCast([*:0]const u8, buff) });
            } else |_| {
                // TODO(remy): do something with the error
            }
        }
    }

    fn renderSelection(self: WidgetText, draw_list: *c.ImDrawList, editor_drawing_offset: Vec2f) void {
        if (!self.selection.active and !self.selection.in_progress) {
            return;
        }

        var i: usize = self.viewport.lines.a;
        var y_offset: f32 = 0;

        while (i < self.viewport.lines.b) : (i += 1) {
            if (self.editor.buffer.getLine(i)) |line| {
                var utf8size = line.utf8size() catch |err| {
                    std.log.err("WidgetText.renderSelection: can't get utf8size of line {d}: {}", .{ i, err });
                    return;
                };

                var viewport_x_offset = @intToFloat(f32, self.viewport.columns.a) * self.one_char_size.a;

                if (i >= self.selection.start.b and i <= self.selection.stop.b) {
                    var start_x = editor_drawing_offset.a;
                    // start of the line or not?
                    if (self.selection.start.b == i) {
                        start_x += @intToFloat(f32, self.selection.start.a) * self.one_char_size.a - viewport_x_offset;
                    }
                    // end of the line or not?
                    var end_x = editor_drawing_offset.a + (@intToFloat(f32, utf8size - 1)) * self.one_char_size.a - viewport_x_offset;
                    if (self.selection.stop.b == i) {
                        end_x = editor_drawing_offset.a + @intToFloat(f32, self.selection.stop.a) * self.one_char_size.a - viewport_x_offset;
                    }
                    // at least a part of this line is selected
                    c.ImDrawList_AddRectFilled(
                        draw_list,
                        ImVec2(start_x, editor_drawing_offset.b + y_offset),
                        ImVec2(end_x, editor_drawing_offset.b + y_offset + self.one_char_size.b),
                        0x66AFAFAF,
                        0.0,
                        0,
                    );
                }
                y_offset += self.one_char_size.b;
            } else |err| {
                std.log.err("WidgetText.renderSelection: can't get line {d}: {}", .{ i, err });
                return;
            }
        }

        return;
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    fn scrollToCursor(self: *WidgetText) void {
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

    /// `isCursorVisible` returns true if the cursor is visible in the window.
    /// TODO(remy): test
    fn isCursorVisible(self: WidgetText) bool {
        return (self.cursor.pos.b >= self.viewport.lines.a and self.cursor.pos.b <= self.viewport.lines.b and
            self.cursor.pos.a >= self.viewport.columns.a and self.cursor.pos.a <= self.viewport.columns.b);
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    fn cursorPosFromWindowPos(self: WidgetText, click_window_pos: Vec2u, editor_drawing_offset: Vec2f) Vec2u {
        var rv = Vec2u{ .a = 0, .b = 0 };

        // remove the offset
        var in_editor = Vec2u{
            .a = click_window_pos.a - @floatToInt(usize, editor_drawing_offset.a),
            .b = click_window_pos.b - @floatToInt(usize, editor_drawing_offset.b),
        };

        rv.a = in_editor.a / @floatToInt(usize, self.one_char_size.a);
        rv.b = in_editor.b / @floatToInt(usize, self.one_char_size.b);

        rv.a += self.viewport.columns.a;
        rv.b += self.viewport.lines.a;

        return rv;
    }

    fn setCursorPos(self: *WidgetText, pos: Vec2u, scroll: bool) void {
        self.cursor.pos = pos;
        if (scroll) {
            self.scrollToCursor();
        }
    }

    fn startSelection(self: *WidgetText, cursor_pos: Vec2u) void {
        self.setInputMode(.Command);

        self.selection.start = cursor_pos;
        self.selection.initial = self.selection.start;
        self.selection.stop = self.selection.start;

        self.selection.in_progress = true;
        self.selection.active = false;
    }

    // TODO(remy): unit test
    fn updateSelection(self: *WidgetText, cursor_pos: Vec2u) void {
        if (self.selection.in_progress) {
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
    fn stopSelection(self: *WidgetText, active: bool) void {
        if (!self.selection.in_progress) {
            return;
        }

        // in all cases, selection isn't in progress anwymore
        self.selection.in_progress = false;

        // selection has stopped where it has been initiated, consider this as a click.
        if (self.selection.stop.a == self.selection.start.a and
            self.selection.stop.b == self.selection.start.b)
        {
            self.setCursorPos(self.selection.initial, false);
            // make sure the position is on text
            self.validateCursorPosition(true);
            // enter insert mode
            self.setInputMode(.Insert);
            // selection inactive
            self.selection.active = false;
            return;
        }

        self.selection.active = active;
    }

    // TODO(remy): unit test
    pub fn paste(self: *WidgetText) !void {
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
    pub fn onCtrlKeyDown(self: *WidgetText, keycode: i32, ctrl: bool, cmd: bool) bool {
        _ = ctrl;
        _ = cmd;
        switch (keycode) {
            'd' => {
                self.moveCursor(Vec2i{ .a = 0, .b = page_move }, true);
            },
            'u' => {
                self.moveCursor(Vec2i{ .a = 0, .b = -page_move }, true);
            },
            'v' => {
                self.paste() catch |err| {
                    std.log.err("WidgetText.onCtrlKeyDown: can't paste: {}", .{err});
                };
                return true;
            },
            else => {},
        }
        return true;
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn onTextInput(self: *WidgetText, txt: []const u8) bool {
        switch (self.input_mode) {
            .Insert => {
                // TODO(remy): selection support
                if (self.editor.insertUtf8Text(self.cursor.pos, txt)) {
                    self.moveCursor(Vec2i{ .a = 1, .b = 0 }, true);
                } else |err| {
                    std.log.err("WidgetText.onTextInput: can't insert utf8 text: {}", .{err});
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
                        self.startSelection(self.cursor.pos);
                    },
                    'y' => {
                        if (self.selection.in_progress or self.selection.active) {
                            self.stopSelection(false);

                            if (self.buildSelectedText()) |selected_text| {
                                var data = selected_text.data.toOwnedSlice();
                                selected_text.deinit();
                                _ = c.SDL_SetClipboardText(@ptrCast([*:0]const u8, data));
                            } else |err| {
                                std.log.err("WidgetText.onTextInput: can't get selected text: {}", .{err});
                            }

                            self.selection.active = false;
                        }
                    },
                    'p' => {
                        self.paste() catch |err| {
                            std.log.err("WidgetText.onTextInput: can't paste: {}", .{err});
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
                            std.log.err("WidgetText.onTextInput: can't delete line: {}", .{err});
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
                            std.log.err("WidgetText.onTextInput: can't get line while executing 'x' input: {}", .{err});
                        }
                        self.editor.deleteUtf8Char(self.cursor.pos, false) catch |err| {
                            std.log.err("WidgetText.onTextInput: can't delete utf8 char while executing 'x' input: {}", .{err});
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
    pub fn onTab(self: *WidgetText, shift: bool) void {
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
    pub fn onMouseWheel(self: *WidgetText, move: Vec2i, visible_cols_and_lines: Vec2u) void {
        if (move.b < 0) {
            self.moveViewport(Vec2i{ .a = 0, .b = page_move }, visible_cols_and_lines);
        } else if (move.b > 0) {
            self.moveViewport(Vec2i{ .a = 0, .b = -page_move }, visible_cols_and_lines);
        }
        if (move.a < 0) {
            self.moveViewport(Vec2i{ .a = -(page_move / 2), .b = 0 }, visible_cols_and_lines);
        } else if (move.a > 0) {
            self.moveViewport(Vec2i{ .a = (page_move / 2), .b = 0 }, visible_cols_and_lines);
        }
    }

    // TODO(remy): unit test
    pub fn onMouseMove(self: *WidgetText, mouse_window_pos: Vec2u, editor_drawing_offset: Vec2f) void {
        // ignore out of the editor click
        if (mouse_window_pos.a < @floatToInt(usize, editor_drawing_offset.a) or mouse_window_pos.b < @floatToInt(usize, editor_drawing_offset.b)) {
            return;
        }

        // ignore movements when not selecting text.
        if (!self.selection.in_progress) {
            return;
        }

        var cursor_pos = self.cursorPosFromWindowPos(mouse_window_pos, editor_drawing_offset);

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
    pub fn onReturn(self: *WidgetText) void {
        switch (self.input_mode) {
            .Insert => self.newLine(),
            else => self.moveCursor(Vec2i{ .a = 0, .b = 1 }, true),
        }
    }

    // TODO(remy):
    // TODO(remy): comment
    /// returns true if the event has been absorbed by the WidgetText.
    pub fn onEscape(self: *WidgetText) bool {
        // stop selection mode
        self.stopSelection(false);
        self.selection.active = false;

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
    pub fn onBackspace(self: *WidgetText) void {
        switch (self.input_mode) {
            .Insert => {
                self.editor.deleteUtf8Char(self.cursor.pos, true) catch |err| {
                    std.log.err("WidgetText.onBackspace: {}", .{err});
                };
                self.moveCursor(Vec2i{ .a = -1, .b = 0 }, true);
            },
            else => {},
        }
    }

    // TODO(remy): unit test
    pub fn onMouseStartSelection(self: *WidgetText, mouse_window_pos: Vec2u, editor_drawing_offset: Vec2f) void {
        if (mouse_window_pos.a < @floatToInt(usize, editor_drawing_offset.a) or mouse_window_pos.b < @floatToInt(usize, editor_drawing_offset.b)) {
            return;
        }

        var cursor_pos = self.cursorPosFromWindowPos(mouse_window_pos, editor_drawing_offset);
        self.startSelection(cursor_pos);
    }

    // TODO(remy): unit test
    pub fn onMouseStopSelection(self: *WidgetText, mouse_window_pos: Vec2u, editor_drawing_offset: Vec2f) void {
        if (mouse_window_pos.a < @floatToInt(usize, editor_drawing_offset.a) or mouse_window_pos.b < @floatToInt(usize, editor_drawing_offset.b)) {
            return;
        }

        self.stopSelection(true);
    }

    // Text edition methods
    // -------------------

    // TODO(remy): comment
    // TODO(remy): unit test
    /// buildSelectedText always returns a string ended with a \0.
    pub fn buildSelectedText(self: WidgetText) !*U8Slice {
        var rv = U8Slice.initEmpty(self.allocator);
        errdefer rv.deinit();

        if (!self.selection.active) {
            return &rv;
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

        return &rv;
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    // TODO(remy): implement smooth movement
    pub fn moveViewport(self: *WidgetText, move: Vec2i, visible_cols_and_lines: Vec2u) void {
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
            self.viewport.lines.b = visible_cols_and_lines.b;
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
            self.viewport.columns.b = visible_cols_and_lines.a;
        } else if (cols_b > longest_visible_line) {
            self.viewport.columns.a = @intCast(usize, @max(0, @intCast(i64, longest_visible_line) - @intCast(i64, visible_cols_and_lines.a)));
            self.viewport.columns.b = longest_visible_line;
        } else {
            self.viewport.columns.a = @intCast(usize, cols_a);
            self.viewport.columns.b = @intCast(usize, cols_b);
        }

        if (self.viewport.columns.b > longest_visible_line) {
            self.viewport.columns.a = @intCast(usize, @max(0, @intCast(i64, longest_visible_line) - @intCast(i64, visible_cols_and_lines.a)));
            self.viewport.columns.b = @max(longest_visible_line, visible_cols_and_lines.a);
        } else {
            self.viewport.columns.b = self.viewport.columns.a + visible_cols_and_lines.a;
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    /// If you want to make sure the cursor is on a valid position, consider
    /// using `validateCursorPosition`.
    pub fn moveCursor(self: *WidgetText, move: Vec2i, scroll: bool) void {
        var cursor_pos = Vec2utoi(self.cursor.pos);
        var line: *U8Slice = undefined;
        var utf8size: usize = 0;

        if (self.editor.buffer.getLine(self.cursor.pos.b)) |l| {
            line = l;
        } else |err| {
            // still, report the error
            std.log.err("WidgetText.moveCursor: can't get line {d}: {}", .{ cursor_pos.b, err });
            return;
        }

        if (line.utf8size()) |size| {
            utf8size = size;
        } else |err| {
            std.log.err("WidgetText.moveCursor: can't get line {d} utf8size: {}", .{ cursor_pos.b, err });
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

        if (self.selection.in_progress) {
            self.updateSelection(self.cursor.pos);
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn validateCursorPosition(self: *WidgetText, scroll: bool) void {
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
            std.log.err("WidgetText.moveCursor: can't get utf8size of the line {d}: {}", .{ self.cursor.pos.b, err });
        }

        if (scroll) {
            self.scrollToCursor();
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn moveCursorSpecial(self: *WidgetText, move: CursorMove, scroll: bool) void {
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
                        std.log.err("WidgetText.moveCursorSpecial.EndOfLine: can't get utf8size of the line: {}", .{err});
                    }
                } else |err| {
                    std.log.err("WidgetText.moveCursorSpecial.EndOfLine: {}", .{err});
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
    pub fn newLine(self: *WidgetText) void {
        self.editor.newLine(self.cursor.pos, false) catch |err| {
            std.log.err("WidgetText.newLine: {}", .{err});
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
    fn setInputMode(self: *WidgetText, input_mode: InputMode) void {
        if (input_mode == .Insert) {
            // stop any selection
            self.stopSelection(false);

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

    // TODO(remy): comment
    pub fn undo(self: *WidgetText) void {
        if (self.editor.undo()) |pos| {
            self.setCursorPos(pos, true);
        } else |err| {
            if (err != EditorError.NothingToUndo) {
                std.log.err("WidgetText.undo: can't undo: {}", .{err});
            }
        }
    }
};

test "widget_text moveCursor" {
    const allocator = std.testing.allocator;
    var app: *App = undefined;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var widget = WidgetText.initWithBuffer(allocator, app, buffer);
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

test "widget_text moveCursorSpecial" {
    const allocator = std.testing.allocator;
    var app: *App = undefined;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var widget = WidgetText.initWithBuffer(allocator, app, buffer);
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

test "widget_text init deinit" {
    const allocator = std.testing.allocator;
    var app: *App = undefined;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    var widget = WidgetText.initWithBuffer(allocator, app, buffer);
    widget.deinit();
}
