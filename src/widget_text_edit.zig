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
const SearchDirection = @import("editor.zig").SearchDirection;
const U8Slice = @import("u8slice.zig").U8Slice;
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;
const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const Vec2utoi = @import("vec.zig").Vec2utoi;
const Vec4u = @import("vec.zig").Vec4u;

const utoi = @import("vec.zig").utoi;
const itou = @import("vec.zig").itou;

const char_space = @import("u8slice.zig").char_space;
const char_tab = @import("u8slice.zig").char_tab;
const char_linereturn = @import("u8slice.zig").char_linereturn;
const string_space = @import("u8slice.zig").string_space;
const string_tab = @import("u8slice.zig").string_tab;

// TODO(remy): where should we define this?
// TODO(remy): comment
// TODO(remy): comment
pub const glyph_offset_before_move = 5;
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
    /// AfterIndentation moves the cursor right until it is not on an indentation space
    AfterIndentation,
};

/// Cursor represents the editing position in the WidgetTextEdit.
/// Its position is in glyph.
/// It is not tab-aware.
pub const Cursor = struct {
    /// pos is the position in glyph.
    /// Use UTF8Iterator if you need help moving in a line per glyph.
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
    /// `line_offset_in_buffer` contains the first visible line (of the buffer) in the current window. With this + the position
    /// of the cursor in the buffer, we can compute where to relatively position the cursor in the window in order to draw it.
    // TODO(remy): consider redrawing the character which is under the cursor in a reverse color to see it above the cursor
    pub fn render(_: Cursor, sdl_renderer: *c.SDL_Renderer, input_mode: InputMode, scaler: Scaler, draw_pos: Vec2u, one_char_size: Vec2u, focused: bool) void {
        if (!focused) {
            Draw.rect(
                sdl_renderer,
                scaler,
                Vec2u{
                    .a = draw_pos.a,
                    .b = draw_pos.b,
                },
                Vec2u{ .a = one_char_size.a, .b = one_char_size.b },
                Colors.white,
            );
            return;
        }

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
            .a = itou(@max(utoi(click_window_pos.a - draw_pos.a) - utoi(text_edit.line_numbers_offset), 0)) / text_edit.one_char_size.a,
            .b = (click_window_pos.b - draw_pos.b) / text_edit.one_char_size.b,
        };

        // line
        // --

        rv.b = in_editor.b;
        rv.b += text_edit.viewport.lines.a;

        if (rv.b < 0) {
            rv.b = 0;
        } else if (rv.b >= text_edit.editor.buffer.lines.items.len) {
            if (text_edit.editor.buffer.lines.items.len > 0) {
                rv.b = text_edit.editor.buffer.lines.items.len - 1;
                var last_line = text_edit.editor.buffer.getLine(text_edit.editor.buffer.lines.items.len - 1) catch |err| {
                    std.log.err("Cursor.posFromWindowPos: can't get last line {d}: {}", .{ rv.b, err });
                    return rv;
                };
                rv.a = last_line.size() - 1;
            } else {
                rv.b = 0;
                rv.a = 0;
            }
            return rv;
        }

        // column
        // --

        var line = text_edit.editor.buffer.getLine(rv.b) catch |err| {
            std.log.err("Cursor.posFromWindowPos: can't get current line {d}: {}", .{ rv.b, err });
            return rv;
        };

        var utf8size = line.utf8size() catch |err| {
            std.log.err("Cursor.posFromWindowPos: can't get current line utf8size {d}: {}", .{ rv.b, err });
            return rv;
        };

        if (in_editor.a + text_edit.viewport.columns.a > utf8size) {
            rv.a = utf8size;
            return rv;
        }

        if (in_editor.a == 0) {
            rv.a = text_edit.viewport.columns.a;
            return rv;
        }

        var tabs_idx: usize = 0;
        var move_done: usize = 0;
        var it = UTF8Iterator.init(line.bytes(), 0) catch |err| {
            std.log.err("Cursor.posFromWindowPos: {}", .{err});
            return rv;
        };

        while (move_done < text_edit.viewport.columns.b) {
            if (it.glyph()[0] == char_tab and tabs_idx == 0) {
                // it is a tab
                tabs_idx = 4;
            }
            if (tabs_idx > 0) {
                tabs_idx -= 1;
            }
            if (tabs_idx == 0) {
                if (!it.next()) {
                    break;
                }
            }

            move_done += 1;
            if (move_done >= text_edit.viewport.columns.a + in_editor.a) {
                rv.a = it.current_glyph;
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
    cursor: Cursor,
    editor: Editor,
    input_mode: InputMode,
    /// render_line_numbers is set to true when the line numbers have to be rendered
    /// It is set to false when the WidgetTextEdit is used as an edit input.
    render_line_numbers: bool,
    /// viewport represents what part of the buffer has to be visible
    /// It is measured in glyphs.
    viewport: WidgetTextEditViewport,
    /// selection in the current editor. It is measured in glyphs.
    selection: WidgetTextEditSelection,
    /// line_numbers_offset is the x offset created by drawing the line numbers
    /// at the left of the editor.
    /// In pixel.
    line_numbers_offset: usize,
    /// visible_cols_and_lines is computed every render and represents how many
    /// columns and lines are visible in the editor.
    visible_cols_and_lines: Vec2u,
    /// one_char_size is computed every render and represents the size of one
    /// glyph rendered in the WidgetTextEdit.
    one_char_size: Vec2u,
    /// last_search contains the last search terms having been used in this WidgetTextEdit.
    last_search: U8Slice,

    // Constructors
    // ------------

    // TODO(remy): comment
    pub fn initWithBuffer(allocator: std.mem.Allocator, buffer: Buffer) WidgetTextEdit {
        return WidgetTextEdit{
            .allocator = allocator,
            .cursor = Cursor.init(),
            .render_line_numbers = true,
            .editor = Editor.init(allocator, buffer),
            .input_mode = InputMode.Command,
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
            .last_search = U8Slice.initEmpty(allocator),
        };
    }

    pub fn deinit(self: *WidgetTextEdit) void {
        self.last_search.deinit();
        self.editor.deinit();
    }

    // Rendering methods
    // -----------------

    /// render renders the WidgetTextEdit.
    /// Renders line number at the left of the widget only if `render_line_numbers` is set to true. Set it to false to
    /// renders an input text.
    /// All positions must be given like if scaling (retina/highdpi) doesn't exist. The scale will be applied internally
    /// using the given `scaler`. `draw_pos`, `widget_size` and `one_char_size` should be in pixel.
    pub fn render(self: *WidgetTextEdit, sdl_renderer: *c.SDL_Renderer, font: Font, scaler: Scaler, draw_pos: Vec2u, widget_size: Vec2u, one_char_size: Vec2u, focused: bool) void {
        self.one_char_size = one_char_size;
        self.visible_cols_and_lines = Vec2u{
            .a = (widget_size.a - self.line_numbers_offset) / @floatToInt(usize, @intToFloat(f32, one_char_size.a)),
            .b = ((widget_size.b) / @floatToInt(usize, @intToFloat(f32, one_char_size.b))) - 1, // FIXME(remy): this -1 is based on nothing
        };
        self.computeViewport();

        var pos = draw_pos;

        // render line numbers
        // it creates a left offset

        var left_offset: usize = 0;

        if (self.render_line_numbers) {
            left_offset = self.renderLineNumbers(sdl_renderer, font, scaler, pos, widget_size, one_char_size);
            pos.a += left_offset;
        }

        // render the lines
        // it also adds a left offset (a small blank)

        left_offset = self.renderLines(font, scaler, pos, one_char_size, focused);
        pos.a += left_offset;

        self.line_numbers_offset = pos.a - draw_pos.a;
    }

    // renderLineNumbers renders the lines number at the left of the widget.
    /// All positions must be given like if scaling (retina/highdpi) doesn't exist. The scale will be applied internally
    /// using the given `scaler`. `draw_pos`, `widget_size` and `one_char_size` should be in pixel.
    /// Returns x offset introduced by drawing the lines numbers
    fn renderLineNumbers(self: WidgetTextEdit, sdl_renderer: *c.SDL_Renderer, font: Font, scaler: Scaler, draw_pos: Vec2u, widget_size: Vec2u, one_char_size: Vec2u) usize {
        var text_pos_x: usize = draw_pos.a + one_char_size.a;

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

            Draw.text(font, scaler, Vec2u{ .a = text_pos_x, .b = y_offset }, text_color, cbuff);

            if (i == self.cursor.pos.b) {
                Draw.fillRect(
                    sdl_renderer,
                    scaler,
                    Vec2u{ .a = draw_pos.a, .b = y_offset },
                    Vec2u{ .a = width, .b = self.one_char_size.b },
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

    /// renderLines renders the lines of text, the selections if any, and the cursor if visible.
    /// All positions must be given like if scaling (retina/highdpi) doesn't exist. The scale will be applied internally
    /// using the given `scaler`. `draw_pos` and `one_char_size` should be in pixel.
    fn renderLines(self: WidgetTextEdit, font: Font, scaler: Scaler, draw_pos: Vec2u, one_char_size: Vec2u, focused: bool) usize {
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

                var it = UTF8Iterator.init(line.bytes(), 0) catch |err| {
                    std.log.err("WidgetTextEdit.renderLinesAndSelection: {}", .{err});
                    return left_blank_offset;
                };

                var tab_idx: usize = 0;
                var move_done: usize = 0;
                var offset: usize = 0; // offset in char, relative to the left of the widget (i.e. right of the line numbers if any)
                var bytes = line.bytes();

                while (offset < self.viewport.columns.b) {
                    if (it.glyph()[0] == char_tab and tab_idx == 0) {
                        tab_idx = tab_spaces;
                    }

                    // render the glyph only if not rendering a tab and we "moved" enough
                    // to be in the viewport
                    if (move_done >= self.viewport.columns.a) {

                        // if we're not currently rendering a tab
                        // we have to draw a glyph

                        if (tab_idx == 0) {
                            var color = self.glyphColor(bytes[it.current_byte..]);
                            _ = Draw.glyph(
                                font,
                                scaler,
                                Vec2u{
                                    .a = draw_pos.a + (offset * one_char_size.a) + left_blank_offset,
                                    .b = draw_pos.b + y_offset,
                                },
                                color,
                                bytes[it.current_byte .. it.current_byte + it.current_glyph_size],
                            );
                        }

                        // draw the selection rectangle if necessary

                        if (self.isSelected(Vec2u{ .a = it.current_glyph, .b = i })) {
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

                        if (self.cursor.pos.a == it.current_glyph and (tab_idx == 4 or tab_idx == 0) and self.cursor.pos.b == i) {
                            self.cursor.render(
                                font.sdl_renderer,
                                self.input_mode,
                                scaler,
                                Vec2u{
                                    .a = draw_pos.a + (offset * one_char_size.a) + left_blank_offset,
                                    .b = draw_pos.b + y_offset,
                                },
                                one_char_size,
                                focused,
                            );
                        }
                    }

                    var done = false;

                    // move in the actual buffer only if we're not in a tab
                    if (tab_idx == 0) {
                        if (!it.next()) {
                            done = true;
                        }
                    } else {
                        // we are currently drawing a tab
                        tab_idx -= 1;
                        if (tab_idx == 0) { // are we done drawing this tab? time to move forward in the idx
                            if (!it.next()) {
                                done = true;
                            }
                        }
                    }

                    // we are done, we will quit this loop.
                    // However we have one last thing to do to check for a edge case: if we are
                    // at the end of the line, and the current position is on the cursor
                    // we have to draw the cursor.
                    // It happens on the very last line of the WidgetTextEdit (and so
                    // for all WidgetTextEdit used as an input field.
                    if (done) {
                        if (i == self.cursor.pos.b and self.cursor.pos.a == it.current_glyph) {
                            self.cursor.render(
                                font.sdl_renderer,
                                self.input_mode,
                                scaler,
                                Vec2u{
                                    .a = draw_pos.a + ((offset + 1) * one_char_size.a) + left_blank_offset,
                                    .b = draw_pos.b + y_offset,
                                },
                                one_char_size,
                                focused,
                            );
                        }
                        break;
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

    /// isSelected returns true if the given glyph is selected in the managed editor.
    fn isSelected(self: WidgetTextEdit, glyph: Vec2u) bool {
        if (self.selection.state == .Inactive) {
            return false;
        }

        if (self.selection.start.a == self.selection.stop.a and
            self.selection.start.b == self.selection.stop.b)
        {
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
            if (self.selection.stop.a > 0 and glyph.a <= self.selection.stop.a - 1) {
                return true;
            }
            return false;
        }

        // starting and ending on this line
        if (self.selection.start.b == self.selection.stop.b and glyph.b == self.selection.start.b and
            glyph.a >= self.selection.start.a and self.selection.stop.a > 0 and glyph.a <= self.selection.stop.a - 1)
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
    fn scrollToCursor(self: *WidgetTextEdit) void {
        // when rendering the line numbers, we use a part of the width
        // this impacts how many glyphs are rendered, we have take this into account while
        // computing when scrolling to follow the cursor.

        var offset_before_move: usize = glyph_offset_before_move;
        if (self.render_line_numbers) {
            offset_before_move += self.line_numbers_offset / self.one_char_size.a;
        }

        // the cursor is above
        if (self.cursor.pos.b < self.viewport.lines.a) {
            var count_lines_visible = self.viewport.lines.b - self.viewport.lines.a;
            self.viewport.lines.a = self.cursor.pos.b;
            self.viewport.lines.b = self.viewport.lines.a + count_lines_visible;
        }

        // the cursor is below
        if (self.cursor.pos.b + glyph_offset_before_move > self.viewport.lines.b) {
            var distance = self.cursor.pos.b + glyph_offset_before_move - self.viewport.lines.b;
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
        if (self.cursor.pos.a + offset_before_move > self.viewport.columns.b) {
            var distance = self.cursor.pos.a + offset_before_move - self.viewport.columns.b;
            self.viewport.columns.a += distance;
            self.viewport.columns.b += distance;
        }
    }

    pub fn setCursorPos(self: *WidgetTextEdit, pos: Vec2u, scroll: bool) void {
        self.cursor.pos = pos;
        if (scroll) {
            self.scrollToCursor();
        }
    }

    pub fn search(self: *WidgetTextEdit, txt: U8Slice, direction: SearchDirection, new_terms: bool) void {
        if (new_terms) {
            self.last_search.deinit();
            self.last_search = U8Slice.initFromSlice(self.allocator, txt.bytes()) catch |err| {
                std.log.err("WidgetTextEdit.search: can't store last search terms: {}", .{err});
                return;
            };
        }

        if (self.editor.search(txt, self.cursor.pos, direction)) |new_cursor_pos| {
            self.setCursorPos(new_cursor_pos, true);
        } else |err| {
            if (err != EditorError.NoSearchResult) {
                std.log.warn("WidgetTextEdit.search: can't search for '{s}' in document '{s}': {}", .{ txt.bytes(), self.editor.buffer.fullpath.bytes(), err });
            }
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

    fn deleteSelection(self: *WidgetTextEdit) void {
        if (self.editor.deleteChunk(self.selection.start, self.selection.stop)) |cursor_pos| {
            self.editor.historyEndBlock();
            self.setCursorPos(cursor_pos, true);
            self.selection.state = .Inactive;
        } else |err| {
            std.log.err("WidgetTextEdit.deleteSelection: can't remove a chunk of data: {}", .{err});
        }
    }

    // TODO(remy): unit test
    /// paste is writing what's available in the clipboard in the WidgetTextEdit.
    pub fn paste(self: *WidgetTextEdit) !void {
        // read data from the clipboard
        var data = c.SDL_GetClipboardText();
        defer c.SDL_free(data);
        // turn into an U8Slice
        var str = try U8Slice.initFromCSlice(self.allocator, data);
        defer str.deinit();
        // paste in the editor
        var new_cursor_pos = try self.editor.paste(self.cursor.pos, str);
        self.editor.historyEndBlock();
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

    /// onTextInput is called when the user has pressed a regular key.
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
                    'i' => {
                        self.setInputMode(.Insert);
                        self.validateCursorPosition(true);
                    },
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
                    // search next & previous
                    'n' => {
                        self.search(self.last_search, .After, false);
                    },
                    'N' => {
                        self.search(self.last_search, .Before, false);
                    },
                    // copy & paste
                    'v' => {
                        self.startSelection(self.cursor.pos, .KeyboardSelection);
                    },
                    'y', 'Y' => {
                        if (self.selection.state != .Inactive) {
                            if (self.buildSelectedText()) |selected_text| {
                                if (selected_text.size() > 0) {
                                    _ = c.SDL_SetClipboardText(@ptrCast([*:0]const u8, selected_text.data.items));
                                }
                                selected_text.deinit();
                            } else |err| {
                                std.log.err("WidgetTextEdit.onTextInput: can't get selected text: {}", .{err});
                            }

                            if (txt[0] == 'Y') {
                                self.deleteSelection();
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
                    'D' => {
                        if (self.editor.deleteLine(@intCast(usize, self.cursor.pos.b))) {
                            self.editor.historyEndBlock();
                            if (self.cursor.pos.b > 0 and self.cursor.pos.b >= self.editor.buffer.lines.items.len) {
                                self.moveCursor(Vec2i{ .a = 0, .b = -1 }, true);
                            }
                            self.validateCursorPosition(true);
                        } else |err| {
                            std.log.err("WidgetTextEdit.onTextInput: can't delete line: {}", .{err});
                        }
                    },
                    'x' => {
                        if (self.selection.state != .Inactive) {
                            self.deleteSelection();
                        } else {
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
                            self.editor.deleteGlyph(self.cursor.pos, .Right) catch |err| {
                                std.log.err("WidgetTextEdit.onTextInput: can't delete utf8 char while executing 'x' input: {}", .{err});
                            };
                        }
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

    /// onTab is called when the user has pressed the Tab key.
    // TODO(remy): support untabbing selection
    pub fn onTab(self: *WidgetTextEdit, shift: bool) void {
        switch (self.input_mode) {
            .Insert => {
                var i: usize = 0;
                while (i < tab_spaces) : (i += 1) {
                    self.editor.insertUtf8Text(self.cursor.pos, string_space) catch |err| {
                        std.log.err("WidgetTextEdit.onTab: can't insert spaces in insert mode: {}", .{err});
                        return;
                    };
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
                                self.editor.deleteGlyph(pos, .Right) catch |err| {
                                    std.log.err("WidgetTextEdit.onTab: can't remove spaces in command mode: {}", .{err});
                                };
                            }
                        }
                    } else |err| {
                        std.log.err("WidgetTextEdit.onTab: can't remove tabs in command mode: {}", .{err});
                        return;
                    }
                } else {
                    while (i < tab_spaces) : (i += 1) {
                        self.editor.insertUtf8Text(pos, string_space) catch |err| {
                            std.log.err("WidgetTextEdit.onTab: can't insert spaces in command mode: {}", .{err});
                        };
                    }
                }
            },
        }

        // make sure the cursor is on a viable position.
        self.validateCursorPosition(true);
    }

    /// onMouseWheel is called when the user is using the wheel of the mouse.
    pub fn onMouseWheel(self: *WidgetTextEdit, move: Vec2i) void {
        var scroll_move = @divTrunc(utoi(self.viewport.lines.b) - utoi(self.viewport.lines.a), 4);
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

    /// onMouseMove is called when the user is moving the cursor on top of the window.
    pub fn onMouseMove(self: *WidgetTextEdit, mouse_window_pos: Vec2u, draw_pos: Vec2u) void {
        // ignore movements when not selecting text.
        if (self.selection.state != .MouseSelection) {
            return;
        }

        // ignore out of the editor click
        if (mouse_window_pos.a < draw_pos.a or mouse_window_pos.b < draw_pos.b) {
            return;
        }

        var cursor_pos = self.cursor.posFromWindowPos(self, mouse_window_pos, draw_pos);

        self.updateSelection(cursor_pos);
        self.setCursorPos(cursor_pos, true);
    }

    /// onReturn is called when the user has pressed Return.
    pub fn onReturn(self: *WidgetTextEdit) void {
        switch (self.input_mode) {
            .Insert => self.newLine(),
            else => self.moveCursor(Vec2i{ .a = 0, .b = 1 }, true),
        }
    }

    /// onEscape is called when the user has pressed Esc.
    /// Calling onEscape will:
    ///   * end current edit block
    ///   * remove selection if any
    ///   * switch the input mode to `Command`
    /// returns true if the event has been absorbed by the WidgetTextEdit.
    pub fn onEscape(self: *WidgetTextEdit) bool {
        // change the history block, we're switching to do something else
        self.editor.historyEndBlock();

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

    /// onBackspace is called when the user has pressed Backspace.
    /// In input mode, delete a char.
    /// In command mode, move the cursor left.
    pub fn onBackspace(self: *WidgetTextEdit) void {
        switch (self.input_mode) {
            .Insert => {
                self.editor.deleteGlyph(self.cursor.pos, .Left) catch |err| {
                    std.log.err("WidgetTextEdit.onBackspace: {}", .{err});
                };
                self.moveCursor(Vec2i{ .a = -1, .b = 0 }, true);
            },
            .Command => {
                self.moveCursor(Vec2i{ .a = -1, .b = 0 }, true);
            },
            else => {},
        }
    }

    /// onMouseStartSelection is called when the user has clicked with the mouse.
    /// When this method is called, the click just happened and the button is still pressed down.
    // TODO(remy): middle & right click
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

    /// onMouseStopSelection is called when the user has stopped pressing with the mouse button.
    // TODO(remy): middle & right click
    pub fn onMouseStopSelection(self: *WidgetTextEdit, mouse_window_pos: Vec2u, draw_pos: Vec2u) void {
        if (mouse_window_pos.a < draw_pos.a or mouse_window_pos.b < draw_pos.b) {
            return;
        }

        // do not completely stop the selection, the user may want to finish it using the keyboard.
        self.stopSelection(.KeyboardSelection);
    }

    // Text edition methods
    // -------------------

    /// buildSelectedText uses the current selection in the WidgetTextEdit to return
    /// the currently selected text.
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

    /// The viewport is the part of editor visible in the current WidgetTextEdit.
    /// moveViewport move that visible "virtual window". `move` must be in glyph.
    // TODO(remy): unit test
    // TODO(remy): implement smooth movement
    pub fn moveViewport(self: *WidgetTextEdit, move: Vec2i) void {
        var cols_a: i64 = 0;
        var cols_b: i64 = 0;
        var lines_a: i64 = 0;
        var lines_b: i64 = 0;

        cols_a = utoi(self.viewport.columns.a) + move.a;
        cols_b = utoi(self.viewport.columns.b) + move.a;

        // lines

        lines_a = utoi(self.viewport.lines.a) + move.b;
        lines_b = utoi(self.viewport.lines.b) + move.b;

        if (lines_a < 0) {
            self.viewport.lines.a = 0;
            self.viewport.lines.b = self.visible_cols_and_lines.b;
        } else if (lines_a > self.editor.buffer.lines.items.len) {
            return;
        } else {
            self.viewport.lines.a = itou(lines_a);
            self.viewport.lines.b = itou(lines_b);
        }

        // +5 here to allow some space on the window right border and the text
        const longest_visible_line = self.editor.buffer.longestLine(self.viewport.lines.a, self.viewport.lines.b) + 5;

        // columns

        if (cols_a < 0) {
            self.viewport.columns.a = 0;
            self.viewport.columns.b = self.visible_cols_and_lines.a;
        } else if (cols_b > longest_visible_line) {
            self.viewport.columns.a = itou(@max(0, utoi(longest_visible_line) - utoi(self.visible_cols_and_lines.a)));
            self.viewport.columns.b = longest_visible_line;
        } else {
            self.viewport.columns.a = itou(cols_a);
            self.viewport.columns.b = itou(cols_b);
        }

        if (self.viewport.columns.b > longest_visible_line) {
            self.viewport.columns.a = itou(@max(0, utoi(longest_visible_line) - utoi(self.visible_cols_and_lines.a)));
            self.viewport.columns.b = @max(longest_visible_line, self.visible_cols_and_lines.a);
        } else {
            self.viewport.columns.b = self.viewport.columns.a + self.visible_cols_and_lines.a;
        }
    }

    /// moveCursor moves the cursor in the current WidgetTextEdit view.
    /// Values passed in `move` are in glyph.
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
            self.cursor.pos.b = itou(cursor_pos.b + move.b);
        }

        // x movement
        if (cursor_pos.a + move.a <= 0 or line.size() == 0) {
            self.cursor.pos.a = 0;
        } else {
            var after_move: usize = itou(cursor_pos.a + move.a);
            if (UTF8Iterator.init(line.bytes(), after_move)) |it| {
                self.cursor.pos.a = it.current_glyph;
            } else |err| {
                std.log.err("WidgetTextEdit.moveCursor: can't compute moveCursor new position: {}", .{err});
            }
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

        if (self.editor.buffer.lines.items.len == 0) {
            self.cursor.pos.a = 0;
            self.cursor.pos.b = 0;
            return;
        }

        if (self.editor.buffer.lines.items[self.cursor.pos.b].utf8size()) |utf8size| {
            if (utf8size == 0) {
                self.cursor.pos.a = 0;
            } else {
                if (self.cursor.pos.a >= utf8size) {
                    // there is a edge case: on the last line, we're OK going one
                    // char out, in order to be able to insert new things there.
                    if (self.cursor.pos.b < utoi(self.editor.buffer.lines.items.len) - 1) {
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
                if (self.editor.buffer.getLine(self.cursor.pos.b)) |line| {
                    if (line.size() == 0) {
                        return;
                    }
                    var it = UTF8Iterator.init(line.bytes(), 0) catch |err| {
                        std.log.err("WidgetTextEdit: can't create an iterator for AfterIndentation: {}", .{err});
                        return;
                    };
                    var i: usize = 0;
                    while (true) {
                        if (std.mem.eql(u8, it.glyph(), string_space) or std.mem.eql(u8, it.glyph(), string_tab)) {
                            i += 1;
                        } else {
                            break;
                        }
                        if (!it.next()) {
                            break;
                        }
                    }
                    self.moveCursor(Vec2i{ .a = @intCast(i64, i), .b = 0 }, true);
                } else |_| {} // TODO(remy): do something with the error
            },
            // TODO(remy): unit test
            .RespectPreviousLineIndent => {
                if (self.cursor.pos.b == 0) {
                    return;
                }
                if (self.editor.buffer.getLine(self.cursor.pos.b - 1)) |line| {
                    if (line.size() == 0) {
                        return;
                    }
                    var start_line_pos = Vec2u{ .a = 0, .b = self.cursor.pos.b };
                    var it = UTF8Iterator.init(line.bytes(), 0) catch |err| {
                        std.log.err("WidgetTextEdit: can't create an iterator for RespectPreviousLineIndent: {}", .{err});
                        return;
                    };
                    while (true) {
                        if (std.mem.eql(u8, it.glyph(), string_space) or std.mem.eql(u8, it.glyph(), string_tab)) {
                            self.editor.insertUtf8Text(start_line_pos, string_space) catch {}; // TODO(remy): do something with the error
                        } else {
                            break;
                        }
                        if (!it.next()) {
                            break;
                        }
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
        self.editor.historyEndBlock();
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

    /// undo cancels the previous change.
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
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var widget = WidgetTextEdit.initWithBuffer(allocator, buffer);
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
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var widget = WidgetTextEdit.initWithBuffer(allocator, buffer);
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
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    var widget = WidgetTextEdit.initWithBuffer(allocator, buffer);
    widget.deinit();
}

test "widget_text_edit isSelected" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var widget = WidgetTextEdit.initWithBuffer(allocator, buffer);

    widget.startSelection(Vec2u{ .a = 3, .b = 0 }, .KeyboardSelection);
    widget.updateSelection(Vec2u{ .a = 13, .b = 1 });

    try expect(widget.isSelected(Vec2u{ .a = 3, .b = 0 }));
    try expect(widget.isSelected(Vec2u{ .a = 13, .b = 0 }));
    try expect(widget.isSelected(Vec2u{ .a = 14, .b = 0 }));
    try expect(widget.isSelected(Vec2u{ .a = 19, .b = 0 })); // outside of the line but still, considered selected and should not crash

    try expect(widget.isSelected(Vec2u{ .a = 0, .b = 1 }));
    try expect(widget.isSelected(Vec2u{ .a = 13, .b = 1 }));
    try expect(!widget.isSelected(Vec2u{ .a = 14, .b = 1 }));
    try expect(!widget.isSelected(Vec2u{ .a = 0, .b = 2 }));

    widget.stopSelection(.KeyboardSelection);
    var txt = try widget.buildSelectedText();
    defer txt.deinit();

    try expect(txt.size() == 23);

    widget.deinit();
}

test "widget_text_edit scrollToCursor" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initFromFile(allocator, "tests/sample_5");
    var widget = WidgetTextEdit.initWithBuffer(allocator, buffer);

    widget.viewport.columns = Vec2u{ .a = 0, .b = 5 };
    widget.viewport.lines = Vec2u{ .a = 0, .b = 5 };

    try expect(widget.cursor.pos.a == 0);
    try expect(widget.cursor.pos.b == 0);

    // move right

    widget.cursor.pos.a = 4;
    widget.scrollToCursor();
    try expect(widget.viewport.columns.a == 4);
    try expect(widget.viewport.columns.b == 9);
    try expect(widget.viewport.lines.a == 0);
    try expect(widget.viewport.lines.b == 5);

    // again

    widget.cursor.pos.a = 5;
    widget.scrollToCursor();
    try expect(widget.viewport.columns.a == 5);
    try expect(widget.viewport.columns.b == 10);
    try expect(widget.viewport.lines.a == 0);
    try expect(widget.viewport.lines.b == 5);

    // back to left

    widget.cursor.pos.a = 0;
    widget.scrollToCursor();
    try expect(widget.viewport.columns.a == 0);
    try expect(widget.viewport.columns.b == 5);
    try expect(widget.viewport.lines.a == 0);
    try expect(widget.viewport.lines.b == 5);

    // move down

    widget.cursor.pos.b = 1;
    widget.scrollToCursor();
    try expect(widget.viewport.columns.a == 0);
    try expect(widget.viewport.columns.b == 5);
    try expect(widget.viewport.lines.a == 1);
    try expect(widget.viewport.lines.b == 6);

    widget.cursor.pos.b = 3;
    widget.scrollToCursor();
    try expect(widget.viewport.columns.a == 0);
    try expect(widget.viewport.columns.b == 5);
    try expect(widget.viewport.lines.a == 3);
    try expect(widget.viewport.lines.b == 8);

    // up again

    widget.cursor.pos.b = 0;
    widget.scrollToCursor();
    try expect(widget.viewport.columns.a == 0);
    try expect(widget.viewport.columns.b == 5);
    try expect(widget.viewport.lines.a == 0);
    try expect(widget.viewport.lines.b == 5);

    widget.deinit();
}
