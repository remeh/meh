const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const Buffer = @import("buffer.zig").Buffer;
const Colors = @import("colors.zig");
const Cursor = @import("cursor.zig").Cursor;
const Direction = @import("app.zig").Direction;
const Draw = @import("draw.zig").Draw;
const Editor = @import("editor.zig").Editor;
const EditorError = @import("editor.zig").EditorError;
const Font = @import("font.zig").Font;
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
pub const glyph_offset_before_move = 5;
// TODO(remy): comment
pub const tab_spaces = 4;

pub const InputMode = enum {
    Command,
    Insert,
    Replace,
    d,
    f,
    F,
    r,
};

pub const CursorMove = enum {
    EndOfLine,
    StartOfLine,
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

pub const LineStatusType = enum {
    Diagnostic,
    GitAdded,
    GitRemoved,
};

pub const LineStatus = struct {
    type: LineStatusType,
    message: ?U8Slice,

    pub fn deinit(self: LineStatus) void {
        if (self.message) |message| {
            message.deinit();
        }
    }
};

/// ScrollBehavior is used to provide the scrolling behavior when moving the cursor: should
/// we move scroll the viewport or immediately center it around the cursor.
pub const ScrollBehavior = enum {
    None,
    Scroll,
    Center,
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
    /// render_horizontal_limits is set to true when 80 and 120 chars limit lines
    /// are rendered.
    render_horizontal_limits: bool,
    /// syntax_highlight is set to true if content of the WidgetTextEdit should
    /// be highlighted
    syntax_highlight: bool,
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
    /// lines_status contains information on every line status (added (git),
    /// with an diag (lsp), etc.).
    lines_status: std.AutoHashMap(usize, LineStatus),

    // Constructors
    // ------------

    /// initWithBuffer inits a WidgetTextEdit to edit the given buffer.
    pub fn initWithBuffer(allocator: std.mem.Allocator, buffer: Buffer) !WidgetTextEdit {
        return WidgetTextEdit{
            .allocator = allocator,
            .cursor = Cursor.init(),
            .render_line_numbers = true,
            .render_horizontal_limits = true,
            .syntax_highlight = true,
            .editor = try Editor.init(allocator, buffer),
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
            .lines_status = std.AutoHashMap(usize, LineStatus).init(allocator),
        };
    }

    pub fn deinit(self: *WidgetTextEdit) void {
        self.last_search.deinit();
        var it = self.lines_status.valueIterator();
        while (it.next()) |line_status| {
            line_status.deinit();
        }
        self.lines_status.deinit();
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
            .a = (widget_size.a - self.line_numbers_offset) / @as(usize, @intFromFloat(@as(f32, @floatFromInt(one_char_size.a)))),
            .b = ((widget_size.b) / @as(usize, @intFromFloat(@as(f32, @floatFromInt(one_char_size.b))))) - 1, // FIXME(remy): this -1 is based on nothing
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

        // horizontal limit lines
        if (self.render_horizontal_limits) {
            self.renderHorizontalLimit(sdl_renderer, scaler, widget_size, draw_pos, one_char_size, left_offset, 80);
            self.renderHorizontalLimit(sdl_renderer, scaler, widget_size, draw_pos, one_char_size, left_offset, 120);
        }

        // refresh the syntax highlighting
        if (self.syntax_highlight) {
            self.refreshSyntaxHighlighting();
        }

        // render the lines
        // it also adds a left offset (a small blank) and makes sure the syntax highlighting is ready

        left_offset = self.renderLines(font, scaler, pos, one_char_size, focused);
        pos.a += left_offset;

        self.line_numbers_offset = pos.a - draw_pos.a;
    }

    /// renderLineNumbers renders the lines number at the left of the widget.
    /// All positions must be given like if scaling (retina/highdpi) doesn't exist. The scale will be applied internally
    /// using the given `scaler`. `draw_pos`, `widget_size` and `one_char_size` should be in pixel.
    /// Returns x offset introduced by drawing the lines numbers
    fn renderLineNumbers(self: WidgetTextEdit, sdl_renderer: *c.SDL_Renderer, font: Font, scaler: Scaler, draw_pos: Vec2u, widget_size: Vec2u, one_char_size: Vec2u) usize {
        const text_pos_x: usize = draw_pos.a + one_char_size.a;

        var carray: [128]u8 = std.mem.zeroes([128]u8);
        const cbuff = &carray;

        var i: usize = self.viewport.lines.a;
        var y_offset: usize = draw_pos.b;

        // measure how wide we need this block to be

        var max_digits: usize = 1;
        var line_count = self.editor.linesCount();
        while (line_count / 10 > 0) {
            max_digits += 1;
            line_count /= 10;
        }
        const width = (max_digits + 2) * one_char_size.a;

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

            if (self.lines_status.get(i)) |status| {
                switch (status.type) {
                    .Diagnostic => text_color = Colors.red,
                    .GitAdded => text_color = Colors.green,
                    .GitRemoved => text_color = Colors.orange,
                }
            }

            Draw.text(font, scaler, Vec2u{ .a = text_pos_x, .b = y_offset }, 0, text_color, cbuff);

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

    /// renderHorizontalLimit is used to render the 80 and 120 chars limit.
    fn renderHorizontalLimit(self: WidgetTextEdit, sdl_renderer: *c.SDL_Renderer, scaler: Scaler, widget_size: Vec2u, draw_pos: Vec2u, one_char_size: Vec2u, left_offset: usize, chars_count: usize) void {
        if (draw_pos.a + (one_char_size.a * chars_count) < self.viewport.columns.a * one_char_size.a) {
            return;
        }

        const x = left_offset + draw_pos.a + (one_char_size.a * chars_count) - self.viewport.columns.a * one_char_size.a;

        Draw.line(
            sdl_renderer,
            scaler,
            .{ .a = x, .b = 0 },
            .{ .a = x, .b = widget_size.b },
            Colors.dark_gray,
        );
    }

    /// renderLines renders the lines of text, the selections if any, and the cursor if visible.
    /// All positions must be given like if scaling (retina/highdpi) doesn't exist. The scale will be applied internally
    /// using the given `scaler`. `draw_pos` and `one_char_size` should be in pixel.
    fn renderLines(self: WidgetTextEdit, font: Font, scaler: Scaler, draw_pos: Vec2u, one_char_size: Vec2u, focused: bool) usize {
        var i: usize = self.viewport.lines.a;
        var y_offset: usize = 0;
        const left_blank_offset: usize = 5;

        // if there is nothing to render, it means we have opened a completely
        // empty buffer. Still, we want to render a cursor or it looks strange.
        if (self.editor.buffer.linesCount() == 0) {
            self.cursor.render(
                font.sdl_renderer,
                self.input_mode,
                scaler,
                Vec2u{
                    .a = draw_pos.a + left_blank_offset,
                    .b = draw_pos.b + y_offset,
                },
                one_char_size,
                focused,
            );

            return left_blank_offset;
        }

        while (i < self.viewport.lines.b and i < self.editor.buffer.linesCount()) : (i += 1) {
            if (self.editor.buffer.getLine(i)) |line| {
                // empty line, just jump a line

                if (line.size() == 0) {
                    if (self.cursor.pos.b == i) {
                        // be still have to draw the cursor though. It happens for lines with no \n,
                        // basically we've just opened a file.
                        self.cursor.render(
                            font.sdl_renderer,
                            self.input_mode,
                            scaler,
                            Vec2u{
                                .a = draw_pos.a + left_blank_offset,
                                .b = draw_pos.b + y_offset,
                            },
                            one_char_size,
                            focused,
                        );
                    }

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
                var offset: usize = 0; // offset in glyph, relative to the left of the widget (i.e. right of the line numbers if any)
                var bytes = line.bytes();
                var line_syntax_highlight = self.editor.syntax_highlighter.getLine(i);

                while (move_done < self.viewport.columns.b) {
                    if (it.glyph()[0] == char_tab and tab_idx == 0) {
                        tab_idx = tab_spaces;
                    }

                    // render the glyph only if not rendering a tab and we "moved" enough
                    // to be in the viewport
                    if (move_done >= self.viewport.columns.a) {

                        // if we're not currently rendering a tab
                        // we have to draw a glyph

                        if (tab_idx == 0) {
                            var color = Colors.light_gray;
                            if (self.syntax_highlight) {
                                color = line_syntax_highlight.getForColumn(it.current_glyph);
                            }
                            Draw.glyph(
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

                if (self.lines_status.get(i)) |line_status| {
                    if (move_done + 4 < self.viewport.columns.b) {
                        const max_size = self.viewport.columns.b - (move_done + 4);
                        if (line_status.message) |message| {
                            Draw.text(font, scaler, Vec2u{
                                .a = draw_pos.a + ((offset + 2) * one_char_size.a) + left_blank_offset,
                                .b = draw_pos.b + y_offset,
                            }, max_size * one_char_size.a, Colors.red, message.bytes());
                        }
                    }
                }

                y_offset += self.one_char_size.b;
            } else |err| {
                std.log.err("WidgetTextEdit.renderLines: error while rendering lines: {}", .{err});
            }
        }

        // special case where there is a diagnostic displayed after the last line
        // of the text eidt
        if (i < self.viewport.lines.b and i == self.editor.buffer.linesCount()) {
            if (self.lines_status.get(i)) |line_status| {
                if (line_status.message) |message| {
                    Draw.text(font, scaler, Vec2u{
                        .a = draw_pos.a + one_char_size.a + left_blank_offset,
                        .b = draw_pos.b + y_offset,
                    }, self.viewport.columns.b * one_char_size.a, Colors.red, message.bytes());
                }
            }
        }

        return left_blank_offset;
    }

    /// TODO(remy): comment me
    fn refreshSyntaxHighlighting(self: *WidgetTextEdit) void {
        var line_start = @max(0, self.viewport.lines.a);
        const line_end = @min(self.viewport.lines.b, self.editor.linesCount());

        while (line_start < line_end) : (line_start += 1) {
            const line = self.editor.buffer.getLine(line_start) catch |err| {
                std.log.err("WidgetTextEdit.refreshSyntaxHighlighting: can't getLine: {}", .{err});
                continue;
            };
            _ = self.editor.syntax_highlighter.refresh(line_start, line) catch |err| {
                std.log.err("WidgetTextEdit.refreshSyntaxHighlighting: can't compute syntax highlight: {}", .{err});
                continue;
            };
        }
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

    /// clearLineStatus empties the diagnostics map.
    pub fn clearLineStatus(self: *WidgetTextEdit, kinds: []const LineStatusType) void {
        var it = self.lines_status.keyIterator();
        while (it.next()) |key| {
            const line_status = self.lines_status.get(key.*).?;
            for (kinds) |kind| {
                if (line_status.type == kind) {
                    _ = self.lines_status.remove(key.*);
                    line_status.deinit();
                }
            }
        }
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

        // the cursor is below
        if (self.cursor.pos.b + glyph_offset_before_move > self.viewport.lines.b) {
            const distance = self.cursor.pos.b + glyph_offset_before_move - self.viewport.lines.b;
            self.viewport.lines.a += distance;
            self.viewport.lines.b += distance;
        }

        // the cursor is above
        if (self.cursor.pos.b < self.viewport.lines.a) {
            const count_lines_visible = self.viewport.lines.b - self.viewport.lines.a;
            self.viewport.lines.a = self.cursor.pos.b;
            self.viewport.lines.b = self.viewport.lines.a + count_lines_visible;
        }

        // start by reseting the viewport to 0
        const count_col_visible = self.viewport.columns.b - self.viewport.columns.a;
        self.viewport.columns.a = 0;
        self.viewport.columns.b = count_col_visible;

        // the cursor is on the right
        if (self.cursor.pos.a + offset_before_move > self.viewport.columns.b) {
            const distance = self.cursor.pos.a + offset_before_move - self.viewport.columns.b;
            self.viewport.columns.a += distance;
            self.viewport.columns.b += distance;
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn centerCursor(self: *WidgetTextEdit) void {
        self.computeViewport();

        const count_lines_visible = self.viewport.lines.b - self.viewport.lines.a;
        if (self.editor.buffer.lines.items.len <= count_lines_visible) {
            // no need to center, the whole file is visible
            return;
        }

        const half = @divTrunc(count_lines_visible, 2);

        if (self.cursor.pos.b < half) {
            // no need to center
            self.viewport.lines.a = 0;
            self.viewport.lines.b = count_lines_visible;
            return;
        }

        self.viewport.lines.a = self.cursor.pos.b - half;
        self.viewport.lines.b = self.viewport.lines.a + count_lines_visible;
    }

    /// setCursorPos moves the cursor at the given position and scroll or center to the cursor
    /// to make sure it's visible.
    pub fn setCursorPos(self: *WidgetTextEdit, pos: Vec2u, scroll: ScrollBehavior) void {
        self.cursor.pos = pos;
        switch (scroll) {
            .Center => self.centerCursor(),
            .Scroll => self.scrollToCursor(),
            .None => {},
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
            self.setCursorPos(new_cursor_pos, .Center); // no need to scroll since we centerCursor right after
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

    /// stopSelection stops current selection and switch to `next_state` instead.
    /// `next_state` is possibly a different selectino state.
    /// If the selection state was a `MouseSelection` and stopping the selection
    /// happens to be on the same position as where it has started,
    /// enters in Input mode instead.
    fn stopSelection(self: *WidgetTextEdit, next_state: SelectionState) void {
        if (self.selection.state == .Inactive) {
            return;
        }

        // selection has stopped where it has been initiated, consider this as a click.
        if (self.selection.state == .MouseSelection and
            self.selection.stop.a == self.selection.start.a and
            self.selection.stop.b == self.selection.start.b)
        {
            self.setCursorPos(self.selection.initial, .None);
            // make sure the position is on text
            self.validateCursorPos(.Scroll);
            // selection inactive
            self.selection.state = .Inactive;
            // enter insert mode
            self.setInputMode(.Insert);
            return;
        }

        self.selection.state = next_state;
    }

    fn deleteSelection(self: *WidgetTextEdit) void {
        if (self.editor.deleteChunk(self.selection.start, self.selection.stop, .Input)) |cursor_pos| {
            self.editor.historyEndBlock();
            self.setCursorPos(cursor_pos, .Scroll);
            self.selection.state = .Inactive;
        } else |err| {
            std.log.err("WidgetTextEdit.deleteSelection: can't remove a chunk of data: {}", .{err});
        }
    }

    // TODO(remy): unit test
    /// paste is writing what's available in the clipboard in the WidgetTextEdit.
    pub fn paste(self: *WidgetTextEdit) !void {
        // read data from the clipboard
        const data = c.SDL_GetClipboardText();
        defer c.SDL_free(data);
        // turn into an U8Slice
        var str = try U8Slice.initFromCSlice(self.allocator, data);
        defer str.deinit();
        // paste in the editor
        const new_cursor_pos = try self.editor.paste(self.cursor.pos, str);
        self.editor.historyEndBlock();
        // move the cursor
        self.setCursorPos(new_cursor_pos, .Scroll);
    }

    // Events methods
    // --------------

    /// onCtrlKeyDown is called when a key has been pressed while a ctrl key is held down.
    pub fn onCtrlKeyDown(self: *WidgetTextEdit, keycode: i32, ctrl: bool, cmd: bool) bool {
        _ = ctrl;
        _ = cmd;

        var move = @divTrunc(@as(i64, @intCast(self.viewport.lines.b)) - @as(i64, @intCast(self.viewport.lines.a)), 2);
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
                self.duplicateLine();
                return true;
            },
            else => {},
        }
        return true;
    }

    /// onArrow is called when an arrow key is pressed to move the cursor.
    /// hjkl are redirected to this method.
    pub fn onArrowKey(self: *WidgetTextEdit, direction: Direction) void {
        switch (direction) {
            .Up => self.moveCursor(Vec2i{ .a = 0, .b = -1 }, true),
            .Down => self.moveCursor(Vec2i{ .a = 0, .b = 1 }, true),
            .Left => {
                self.moveCursor(Vec2i{ .a = -1, .b = 0 }, true);
                self.cursor.max_last_col_pos = self.cursor.pos.a;
            },
            .Right => {
                self.moveCursor(Vec2i{ .a = 1, .b = 0 }, true);
                self.cursor.max_last_col_pos = self.cursor.pos.a;
            },
        }

        // restore the column on up/down movement
        if (direction == .Up or direction == .Down) {
            const col = @max(self.cursor.max_last_col_pos, self.cursor.pos.a);
            self.cursor.max_last_col_pos = col;

            if (self.cursor.pos.a < col) {
                self.moveCursor(Vec2i{ .a = @as(i64, @intCast(col - self.cursor.pos.a)), .b = 0 }, false);
                self.validateCursorPos(.Scroll);
            }
        }
    }

    /// onTextInput is called when the user has pressed a regular key.
    pub fn onTextInput(self: *WidgetTextEdit, txt: []const u8) bool {
        switch (self.input_mode) {
            .Insert => {
                if (self.editor.insertUtf8Text(self.cursor.pos, txt, .Input)) {
                    self.moveCursor(Vec2i{ .a = 1, .b = 0 }, true);
                } else |err| {
                    std.log.err("WidgetTextEdit.onTextInput: can't insert utf8 text: {}", .{err});
                }
            },
            .r, .Replace => {
                // make sure we're not trying to replace the very last
                // character of the current line, which is the \n of the
                // line.
                if (self.editor.buffer.getLine(self.cursor.pos.b)) |line| {
                    const utf8size = line.utf8size() catch 1;
                    if (self.cursor.pos.a == utf8size - 1) {
                        std.log.warn("WidgetTextEdit.onTextInput: tried to replace last character of the line", .{});
                        // only one glyph to change in this mode
                        if (self.input_mode == .r) {
                            self.setInputMode(.Command);
                        }

                        return true;
                    }
                } else |err| {
                    std.log.err("WidgetTextEdit.onTextInput: can't check if last character: {}", .{err});
                }

                self.editor.deleteGlyph(self.cursor.pos, .Right, .Input) catch |err| {
                    std.log.err("WidgetTextEdit.onTextInput: can't delete utf8 char while executing 'r' input: {}", .{err});
                    return true;
                };
                if (self.editor.insertUtf8Text(self.cursor.pos, txt, .Input)) {
                    if (self.input_mode == .Replace) {
                        self.moveCursor(Vec2i{ .a = 1, .b = 0 }, true);
                    }
                } else |err| {
                    std.log.err("WidgetTextEdit.onTextInput: can't replace utf8 text: {}", .{err});
                }

                // only one glyph to change in this mode
                if (self.input_mode == .r) {
                    self.setInputMode(.Command);
                }
            },
            .f, .F => {
                var direction = SearchDirection.After;
                if (self.input_mode == .F) {
                    direction = SearchDirection.Before;
                }
                const new_pos = self.editor.findGlyphInLine(
                    self.cursor.pos,
                    txt,
                    direction,
                ) catch |err| {
                    std.log.err("WidgetTextEdit.onTextInput: can't find glyph in line: {}", .{err});
                    return true;
                };
                self.setCursorPos(new_pos, .Scroll);
                if (self.selection.state != .Inactive) {
                    self.updateSelection(new_pos);
                }

                self.setInputMode(.Command);
            },
            .d => {
                switch (txt[0]) {
                    // delete the word under the cursor
                    'i' => {
                        const word_pos = self.editor.wordPosAt(self.cursor.pos) catch |err| {
                            std.log.err("WidgetTextEdit.onTextInput: di: {}", .{err});
                            return true;
                        };
                        const cursor_pos = self.editor.deleteChunk(
                            Vec2u{ .a = word_pos.a, .b = self.cursor.pos.b },
                            Vec2u{ .a = word_pos.b, .b = self.cursor.pos.b },
                            .Input,
                        ) catch |err| {
                            std.log.err("WidgetTextEdit.onTextInput: di: can't delete chunk: {}", .{err});
                            return true;
                        };
                        self.setCursorPos(cursor_pos, .Scroll);
                        self.setInputMode(.Insert);
                    },
                    // delete the line
                    'd' => {
                        self.deleteLine();
                        self.setInputMode(.Command);
                    },
                    else => {
                        self.setInputMode(.Command);
                    },
                }
            },
            else => {
                switch (txt[0]) {
                    // movements
                    'h' => self.onArrowKey(.Left),
                    'j' => self.onArrowKey(.Down),
                    'k' => self.onArrowKey(.Up),
                    'l' => self.onArrowKey(.Right),
                    'g' => self.moveCursorSpecial(CursorMove.StartOfBuffer, true),
                    'G' => self.moveCursorSpecial(CursorMove.EndOfBuffer, true),
                    'd' => self.setInputMode(.d),
                    'f' => self.setInputMode(.f),
                    'F' => self.setInputMode(.F),
                    'r' => self.setInputMode(.r),
                    'R' => self.setInputMode(.Replace),
                    'V' => {
                        self.moveCursorSpecial(.StartOfLine, false);
                        self.startSelection(self.cursor.pos, .KeyboardSelection);
                        self.moveCursorSpecial(.NextLine, true);
                        self.moveCursorSpecial(.StartOfLine, true);
                        self.updateSelection(self.cursor.pos);
                    },
                    'b' => self.moveCursorSpecial(CursorMove.PreviousSpace, true),
                    'e' => self.moveCursorSpecial(CursorMove.NextSpace, true),
                    // start inserting
                    'i' => {
                        self.setInputMode(.Insert);
                        self.validateCursorPos(.Scroll);
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
                    // search
                    'n' => {
                        self.search(self.last_search, .After, false);
                    },
                    'N' => {
                        self.search(self.last_search, .Before, false);
                    },
                    '*' => {
                        if (self.editor.wordAt(self.cursor.pos)) |word| {
                            _ = self.editor.syntax_highlighter.setHighlightWord(word);
                            self.last_search.deinit();
                            const data = U8Slice.initFromSlice(self.allocator, word) catch |err| {
                                std.log.err("WidgetTextEdit.onTextInput: can't store last search: {}", .{err});
                                return false;
                            };
                            self.last_search = data;
                        } else |err| {
                            std.log.err("can't read word under the cursor: {}", .{err});
                        }
                    },
                    // copy & paste
                    'v' => {
                        self.startSelection(self.cursor.pos, .KeyboardSelection);
                    },
                    'y', 'Y' => {
                        if (self.selection.state != .Inactive) {
                            if (self.buildSelectedText()) |selected_text| {
                                if (selected_text.size() > 0) {
                                    _ = c.SDL_SetClipboardText(@as([*:0]const u8, @ptrCast(selected_text.data.items)));
                                }
                                selected_text.deinit();
                            } else |err| {
                                std.log.err("WidgetTextEdit.onTextInput: can't get selected text: {}", .{err});
                                return true;
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
                    'z' => self.centerCursor(),
                    'D' => self.editor.deleteAfter(self.cursor.pos),
                    'J' => {
                        self.moveCursorSpecial(CursorMove.EndOfLine, true);
                        self.editor.appendNextLine(self.cursor.pos) catch |err| {
                            std.log.err("WidgetTextEdit.onTextInput: can't append next line: {}", .{err});
                        };
                    },
                    'E' => self.deleteLine(),
                    'x' => {
                        if (self.selection.state != .Inactive) {
                            self.deleteSelection();
                        } else {
                            // edge-case: last char of the line
                            if (self.editor.buffer.getLine(self.cursor.pos.b)) |line| {
                                if (line.utf8size()) |size| {
                                    const last_line: bool = (self.cursor.pos.b == (self.editor.buffer.lines.items.len - 1));
                                    if ((self.cursor.pos.a == size - 1 and !last_line) // normal line
                                    or
                                        (self.cursor.pos.a == size and last_line)) // very last line
                                    {
                                        // special case, we don't want to do delete anything
                                        return true;
                                    }
                                } else |_| {}
                            } else |err| {
                                std.log.err("WidgetTextEdit.onTextInput: can't get line while executing 'x' input: {}", .{err});
                                return true;
                            }
                            self.editor.deleteGlyph(self.cursor.pos, .Right, .Input) catch |err| {
                                std.log.err("WidgetTextEdit.onTextInput: can't delete utf8 char while executing 'x' input: {}", .{err});
                                return true;
                            };
                        }
                    },
                    // undo & redo
                    'u' => self.undo(),
                    'U' => self.redo(),
                    else => return false,
                }
            },
        }
        return true;
    }

    /// onTab is called when the user has pressed the Tab key.
    pub fn onTab(self: *WidgetTextEdit, shift: bool) void {
        switch (self.input_mode) {
            .Insert => {
                var i: usize = 0;
                while (i < tab_spaces) : (i += 1) {
                    self.editor.insertUtf8Text(self.cursor.pos, string_space, .Input) catch |err| {
                        std.log.err("WidgetTextEdit.onTab: can't insert spaces in insert mode: {}", .{err});
                        return;
                    };
                }
                self.moveCursor(Vec2i{ .a = 4, .b = 0 }, true);
            },
            else => {
                var line_idx: usize = switch (self.selection.state) {
                    .Inactive => self.cursor.pos.b,
                    else => self.selection.start.b,
                };
                const line_idx_end = switch (self.selection.state) {
                    .Inactive => self.cursor.pos.b + 1,
                    else => self.selection.stop.b + 1,
                };
                while (line_idx < line_idx_end) {
                    var i: usize = 0;
                    const pos = Vec2u{ .a = 0, .b = line_idx };
                    if (shift) {
                        if (self.editor.buffer.getLine(pos.b)) |line| {
                            while (i < tab_spaces) : (i += 1) {
                                if (line.size() > 0 and line.data.items[0] == char_space) {
                                    self.editor.deleteGlyph(pos, .Right, .Input) catch |err| {
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
                            self.editor.insertUtf8Text(pos, string_space, .Input) catch |err| {
                                std.log.err("WidgetTextEdit.onTab: can't insert spaces in command mode: {}", .{err});
                            };
                        }
                    }
                    line_idx += 1;
                }
            },
        }

        // make sure the cursor is on a viable position.
        self.validateCursorPos(.Scroll);
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

        const cursor_pos = self.cursor.posFromWindowPos(self, mouse_window_pos, draw_pos);
        self.setCursorPos(cursor_pos, .Scroll);

        // validateCursorPos will validate that the cursor is at a proper position
        // updating self.cursor.pos if necessary.
        // WARNING: after this call, cursor_pos should not be used anymore.
        self.validateCursorPos(.None);
        self.updateSelection(self.cursor.pos);
    }

    /// onReturn is called when the user has pressed Return.
    pub fn onReturn(self: *WidgetTextEdit, ctrl: bool) void {
        switch (self.input_mode) {
            .Insert => {
                self.newLine();
                if (self.cursor.pos.b > 0) {
                    var line = self.editor.buffer.getLine(self.cursor.pos.b - 1) catch {
                        std.log.err("WidgetTextEdit.onReturn: can't get previous line", .{});
                        return;
                    };
                    if (line.isOnlyWhitespace()) {
                        line.reset();
                        line.appendConst("\n") catch {
                            std.log.err("WidgetTextEdit.onReturn: can't recreate previous empty line properly", .{});
                        };
                    }
                }
            },
            else => {
                if (ctrl) {
                    self.moveCursorSpecial(CursorMove.EndOfLine, true);
                    self.newLine();
                    self.setInputMode(.Insert);
                } else {
                    self.moveCursor(Vec2i{ .a = 0, .b = 1 }, true);
                }
            },
        }
    }

    /// onEscape is called when the user has pressed Esc.
    /// Calling onEscape will:
    ///   * end current edit block
    ///   * remove selection if any
    ///   * clean the line if it's only composed of whitespaces
    ///   * switch the input mode to `Command`
    pub fn onEscape(self: *WidgetTextEdit) void {
        // change the history block, we're switching to do something else
        self.editor.historyEndBlock();

        // stop selection mode
        self.stopSelection(.Inactive);

        // do not highlight anything anymore
        _ = self.editor.syntax_highlighter.setHighlightWord(null);

        // check if we want to clear current line from whitespaces
        if (self.editor.buffer.getLine(self.cursor.pos.b)) |line| {
            if (line.isOnlyWhitespace()) {
                // we want to clean the line from every white spaces
                self.moveCursorSpecial(.EndOfLine, true);
                while (self.cursor.pos.a > 0) {
                    self.editor.deleteGlyph(self.cursor.pos, .Left, .Input) catch |err| {
                        std.log.err("WidgetTextEdit.onEscape: can't clear the line: {}", .{err});
                    };
                    self.moveCursor(Vec2i{ .a = -1, .b = 0 }, false);
                }
            }
        } else |err| {
            std.log.err("WidgetTextEdit.onEscape: can't get current line to reset whitespaces: {}", .{err});
        }

        self.input_mode = InputMode.Command;
    }

    /// onBackspace is called when the user has pressed Backspace.
    /// In input mode, delete a char.
    /// In command mode, move the cursor left.
    pub fn onBackspace(self: *WidgetTextEdit) void {
        switch (self.input_mode) {
            .Insert => {
                self.editor.deleteGlyph(self.cursor.pos, .Left, .Input) catch |err| {
                    std.log.err("WidgetTextEdit.onBackspace: {}", .{err});
                };
                self.moveCursor(Vec2i{ .a = -1, .b = 0 }, true);
            },
            .Command, .Replace => {
                self.moveCursor(Vec2i{ .a = -1, .b = 0 }, true);
            },
            else => {},
        }
    }

    pub fn onSpace(self: *WidgetTextEdit, shift: bool) void {
        switch (self.input_mode) {
            .Command => {
                // jump to next diagnostic
                var it = self.lines_status.keyIterator();
                var keys = std.ArrayList(usize).init(self.allocator);
                defer keys.deinit();

                while (it.next()) |key| {
                    keys.append(key.*) catch |err| {
                        std.log.err("can't find next diagnostic: {}", .{err});
                        return;
                    };
                }

                if (shift) {
                    std.sort.insertion(usize, keys.items, {}, std.sort.desc(usize));
                } else {
                    std.sort.insertion(usize, keys.items, {}, std.sort.asc(usize));
                }

                for (keys.items) |line| {
                    if ((!shift and line > self.cursor.pos.b) or (shift and line < self.cursor.pos.b)) {
                        self.goToLine(line, .Center);
                        break;
                    }
                }
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
        const cursor_pos = self.cursor.posFromWindowPos(self, mouse_window_pos, draw_pos);
        self.setCursorPos(cursor_pos, .None); // no need to scroll here we scroll next line
        self.validateCursorPos(.Scroll);

        // use the position (which may have been corrected) as the selection start position
        self.startSelection(self.cursor.pos, .MouseSelection);

        const word: ?[]const u8 = self.editor.wordAt(self.cursor.pos) catch null;
        const has_changed = self.editor.syntax_highlighter.setHighlightWord(word);
        if (has_changed) {
            self.refreshSyntaxHighlighting();
        }
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

    /// deleteLine deletes the line where is the cursor.
    pub fn deleteLine(self: *WidgetTextEdit) void {
        self.editor.deleteLine(@as(usize, @intCast(self.cursor.pos.b)), .Input);
        self.editor.historyEndBlock();
        self.validateCursorPos(.Scroll);
        self.stopSelection(.Inactive);
    }

    /// duplicateLine duplicates the line under the cursor.
    // TODO(remy): unit test
    // FIXME(remy): seems to crash the app? sometimes?
    pub fn duplicateLine(self: *WidgetTextEdit) void {
        if (self.editor.buffer.getLine(self.cursor.pos.b)) |line| {
            self.moveCursorSpecial(.EndOfLine, false);
            self.editor.newLine(self.cursor.pos, .Input) catch |err| {
                std.log.err("WidgetTextEdit.duplicateLine: on newLine {}", .{err});
                return;
            };
            self.moveCursorSpecial(.NextLine, false);
            self.moveCursorSpecial(.StartOfLine, false);
            self.editor.insertUtf8Text(self.cursor.pos, line.bytes()[0 .. line.bytes().len - 1], .Input) catch |err| {
                std.log.err("WidgetTextEdit.duplicateLine: on insert text {}", .{err});
                return;
            };
            self.moveCursorSpecial(.EndOfLine, true);
        } else |err| {
            std.log.err("WidgetTextEdit.duplicateLine: {}", .{err});
        }
    }

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
                const start_pos = try line.utf8pos(self.selection.start.a);
                try rv.appendConst(line.bytes()[start_pos..line.size()]);
            } else if (i == self.selection.start.b and i == self.selection.stop.b) {
                // selection starting somewhere in the first line and ending in the same
                const start_pos = try line.utf8pos(self.selection.start.a);
                const end_pos = try line.utf8pos(self.selection.stop.a);
                try rv.appendConst(line.bytes()[start_pos..end_pos]);
            } else if (i != self.selection.start.b and i == self.selection.stop.b) {
                const end_pos = try line.utf8pos(self.selection.stop.a);
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
        var longest_visible_line = self.editor.buffer.longestLine(self.viewport.lines.a, self.viewport.lines.b) catch |err| {
            std.log.err("WidgetTextEdit.moveViewport: can't get longest line: {}", .{err});
            return;
        };
        longest_visible_line += 5;

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

    /// moveCursor applies a relative move the cursor in the current WidgetTextEdit view.
    /// Values passed in `move` are in glyph.
    /// `scroll` forces the viewport to make the cursor visible.
    /// If you want to make sure the cursor is on a valid position, consider
    /// using `validateCursorPos`. Note that `validateCursorPos(.Scroll)` is
    /// called if `scroll` is set to true.
    pub fn moveCursor(self: *WidgetTextEdit, move: Vec2i, scroll: bool) void {
        const cursor_pos = Vec2utoi(self.cursor.pos);
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
            const after_move: usize = itou(cursor_pos.a + move.a);
            if (UTF8Iterator.init(line.bytes(), after_move)) |it| {
                self.cursor.pos.a = it.current_glyph;
            } else |err| {
                std.log.err("WidgetTextEdit.moveCursor: can't compute moveCursor new position: {}", .{err});
            }
        }

        if (scroll) {
            self.validateCursorPos(.Scroll);
        }

        if (self.selection.state == .KeyboardSelection) {
            self.updateSelection(self.cursor.pos);
        }
    }

    /// validateCursorPos validates that the cursor is on a valid position, moves the cursor if it is not the case.
    pub fn validateCursorPos(self: *WidgetTextEdit, scroll: ScrollBehavior) void {
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

        switch (scroll) {
            .Center => self.centerCursor(),
            .Scroll => self.scrollToCursor(),
            .None => {},
        }
    }

    /// moveCursorSpecial applies a special movement to the cursor. See the enum `CursorMove`.
    pub fn moveCursorSpecial(self: *WidgetTextEdit, move: CursorMove, scroll: bool) void {
        var scrolled = false;
        switch (move) {
            .EndOfLine => {
                if (self.editor.buffer.getLine(self.cursor.pos.b)) |l| {
                    if (l.utf8size()) |utf8size| {
                        if (l.bytes().len > 0 and l.bytes()[l.bytes().len - 1] == char_linereturn) {
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
                self.cursor.max_last_col_pos = 0;
            },
            .StartOfBuffer => {
                self.cursor.pos.a = 0;
                self.cursor.pos.b = 0;
                self.cursor.max_last_col_pos = 0;
            },
            .EndOfBuffer => {
                self.cursor.pos.b = self.editor.buffer.lines.items.len - 1;
                self.moveCursorSpecial(CursorMove.EndOfLine, scroll);
                scrolled = scroll;
            },
            // TODO(remy): unit test
            .NextSpace => {
                if (self.editor.findGlyphInLine(self.cursor.pos, " ", SearchDirection.After)) |new_pos| {
                    self.setCursorPos(new_pos, .Scroll);
                } else |err| {
                    std.log.err("WidgetTextEdit.moveCursorSpecial.NextSpace: {}", .{err});
                }
            },
            // TODO(remy): unit test
            .PreviousSpace => {
                if (self.editor.findGlyphInLine(self.cursor.pos, " ", SearchDirection.Before)) |new_pos| {
                    self.setCursorPos(new_pos, .Scroll);
                } else |err| {
                    std.log.err("WidgetTextEdit.moveCursorSpecial.NextSpace: {}", .{err});
                }
            },
            .NextLine => {
                self.moveCursor(Vec2i{ .a = 0, .b = 1 }, scroll);
                self.cursor.max_last_col_pos = 0;
                scrolled = scroll;
            },
            .PreviousLine => {
                self.moveCursor(Vec2i{ .a = 0, .b = -1 }, scroll);
                self.cursor.max_last_col_pos = 0;
                scrolled = scroll;
            },
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
                    self.moveCursor(Vec2i{ .a = @as(i64, @intCast(i)), .b = 0 }, true);
                } else |_| {} // TODO(remy): do something with the error
            },
            .RespectPreviousLineIndent => {
                if (self.cursor.pos.b == 0) {
                    return;
                }
                if (self.editor.buffer.getLine(self.cursor.pos.b - 1)) |line| {
                    if (line.size() == 0) {
                        return;
                    }
                    const start_line_pos = Vec2u{ .a = 0, .b = self.cursor.pos.b };
                    var it = UTF8Iterator.init(line.bytes(), 0) catch |err| {
                        std.log.err("WidgetTextEdit: can't create an iterator for RespectPreviousLineIndent: {}", .{err});
                        return;
                    };
                    while (true) {
                        if (std.mem.eql(u8, it.glyph(), string_space)) {
                            self.editor.insertUtf8Text(start_line_pos, string_space, .Input) catch {}; // TODO(remy): do something with the error
                        } else if (std.mem.eql(u8, it.glyph(), string_tab)) {
                            self.editor.insertUtf8Text(start_line_pos, string_tab, .Input) catch {}; // TODO(remy): do something with the error
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
            self.validateCursorPos(.Scroll);
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn newLine(self: *WidgetTextEdit) void {
        self.editor.newLine(self.cursor.pos, .Input) catch |err| {
            std.log.err("WidgetTextEdit.newLine: {}", .{err});
            return;
        };
        self.moveCursorSpecial(CursorMove.NextLine, true);
        self.moveCursorSpecial(CursorMove.StartOfLine, true);
        self.moveCursorSpecial(CursorMove.RespectPreviousLineIndent, true);
        self.moveCursorSpecial(CursorMove.AfterIndentation, true);
        self.editor.historyEndBlock();
    }

    // Others
    // ------

    /// setInputMode switches to the given input_mode.
    /// Stops selection if any and if entering in Insert mode.
    pub fn setInputMode(self: *WidgetTextEdit, input_mode: InputMode) void {
        if (input_mode == .Insert) {
            // stop any selection
            self.stopSelection(.Inactive);
        }
        self.input_mode = input_mode;
    }

    /// goToLine moves the cursor to the given line.
    /// First line starts at 0.
    pub fn goToLine(self: *WidgetTextEdit, line_number: usize, scroll: ScrollBehavior) void {
        const new_pos = Vec2u{ .a = self.cursor.pos.a, .b = line_number };
        self.setCursorPos(new_pos, .None); // no need to scroll here, we'll do it next function call
        self.validateCursorPos(scroll);
    }

    /// goToCol moves the cursor to the given column.
    /// First column starts at 0.
    pub fn goToColumn(self: *WidgetTextEdit, col: usize, scroll: ScrollBehavior) void {
        const new_pos = Vec2u{ .a = col, .b = self.cursor.pos.b };
        self.setCursorPos(new_pos, .None); // no need to scroll here, we'll do it next function call
        self.validateCursorPos(scroll);
    }

    /// goTo moves the cursor to the given line and column.
    /// First line starts at 1.
    pub fn goTo(self: *WidgetTextEdit, position: Vec2u, scroll: ScrollBehavior) void {
        self.goToLine(position.b, .None);
        self.goToColumn(position.a, scroll);
    }

    /// undo cancels the previous change.
    pub fn undo(self: *WidgetTextEdit) void {
        if (self.editor.undo()) |pos| {
            self.setCursorPos(pos, .Center);
        } else |err| {
            if (err != EditorError.NothingToUndo) {
                std.log.err("WidgetTextEdit.undo: can't undo: {}", .{err});
            }
        }
    }

    /// redo reapplies a change previously undone.
    pub fn redo(self: *WidgetTextEdit) void {
        if (self.editor.redo()) |pos| {
            self.setCursorPos(pos, .Center);
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
    var widget = try WidgetTextEdit.initWithBuffer(allocator, buffer);
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
    var widget = try WidgetTextEdit.initWithBuffer(allocator, buffer);
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

    buffer = try Buffer.initFromFile(allocator, "tests/sample_5");
    widget = try WidgetTextEdit.initWithBuffer(allocator, buffer);

    // AfterIndentation

    widget.cursor.pos = Vec2u{ .a = 0, .b = 5 };
    widget.moveCursorSpecial(CursorMove.AfterIndentation, true);
    try expect(widget.cursor.pos.a == 4);

    widget.cursor.pos = Vec2u{ .a = 0, .b = 6 };
    widget.moveCursorSpecial(CursorMove.AfterIndentation, true);
    try expect(widget.cursor.pos.a == 1);

    widget.cursor.pos = Vec2u{ .a = 0, .b = 7 };
    widget.moveCursorSpecial(CursorMove.AfterIndentation, true);
    try expect(widget.cursor.pos.a == 0);

    // RespectPreviousLineIndent

    var line = try widget.editor.buffer.getLine(7);
    try expect(line.bytes()[0] == '\n');
    widget.cursor.pos = Vec2u{ .a = 0, .b = 7 };
    widget.moveCursorSpecial(CursorMove.RespectPreviousLineIndent, true);
    try expect(widget.cursor.pos.a == 0);
    try expect(line.bytes()[0] == '\t');

    widget.cursor.pos = Vec2u{ .a = 0, .b = 6 };
    widget.moveCursorSpecial(CursorMove.RespectPreviousLineIndent, true);
    line = try widget.editor.buffer.getLine(6);
    try expect(widget.cursor.pos.a == 0);
    try expect(std.mem.eql(u8, line.bytes()[0..6], "    \tO"));

    widget.deinit();
}

test "widget_text_edit init deinit" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.initFromFile(allocator, "tests/sample_1");
    var widget = try WidgetTextEdit.initWithBuffer(allocator, buffer);
    widget.deinit();
}

test "widget_text_edit isSelected" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var widget = try WidgetTextEdit.initWithBuffer(allocator, buffer);

    widget.startSelection(Vec2u{ .a = 3, .b = 0 }, .KeyboardSelection);
    widget.updateSelection(Vec2u{ .a = 13, .b = 1 });

    try expect(widget.isSelected(Vec2u{ .a = 3, .b = 0 }));
    try expect(widget.isSelected(Vec2u{ .a = 13, .b = 0 }));
    try expect(widget.isSelected(Vec2u{ .a = 14, .b = 0 }));
    try expect(widget.isSelected(Vec2u{ .a = 19, .b = 0 })); // outside of the line but still, considered selected and should not crash

    try expect(widget.isSelected(Vec2u{ .a = 0, .b = 1 }));
    try expect(widget.isSelected(Vec2u{ .a = 12, .b = 1 }));
    try expect(!widget.isSelected(Vec2u{ .a = 13, .b = 1 }));
    try expect(!widget.isSelected(Vec2u{ .a = 14, .b = 1 }));
    try expect(!widget.isSelected(Vec2u{ .a = 0, .b = 2 }));

    widget.stopSelection(.KeyboardSelection);
    var txt = try widget.buildSelectedText();
    defer txt.deinit();

    try expect(txt.size() == 23);
    try expect(widget.selection.state == .KeyboardSelection);

    widget.deinit();
}

test "widget_text_edit stopSelection enters Input" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.initFromFile(allocator, "tests/sample_2");
    var widget = try WidgetTextEdit.initWithBuffer(allocator, buffer);

    widget.startSelection(Vec2u{ .a = 3, .b = 0 }, .MouseSelection);
    widget.stopSelection(.KeyboardSelection);

    try expect(widget.input_mode == .Insert);
    try expect(widget.selection.state == .Inactive);

    widget.deinit();
}

test "widget_text_edit scrollToCursor" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.initFromFile(allocator, "tests/sample_5");
    var widget = try WidgetTextEdit.initWithBuffer(allocator, buffer);

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

test "widget_text_edit validate_cursor_pos" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.initFromFile(allocator, "tests/sample_5");
    var widget = try WidgetTextEdit.initWithBuffer(allocator, buffer);

    widget.setCursorPos(Vec2u{ .a = 3, .b = 4 }, .Scroll);
    widget.validateCursorPos(.Scroll);
    try expect(widget.cursor.pos.a == 3);
    try expect(widget.cursor.pos.b == 4);

    widget.setCursorPos(Vec2u{ .a = 54, .b = 2 }, .Scroll);
    widget.validateCursorPos(.Scroll);
    try expect(widget.cursor.pos.a == 54);
    try expect(widget.cursor.pos.b == 2);

    widget.setCursorPos(Vec2u{ .a = 200, .b = 6 }, .Scroll);
    widget.validateCursorPos(.Scroll);
    try expect(widget.cursor.pos.a == 22);
    try expect(widget.cursor.pos.b == 6);

    widget.setCursorPos(Vec2u{ .a = 200, .b = 5 }, .Scroll);
    widget.validateCursorPos(.Scroll);
    try expect(widget.cursor.pos.a == 29);
    try expect(widget.cursor.pos.b == 5);

    widget.setCursorPos(Vec2u{ .a = 200, .b = 9 }, .Scroll);
    widget.validateCursorPos(.Scroll);
    try expect(widget.cursor.pos.a == 0);
    try expect(widget.cursor.pos.b == 9);

    widget.deinit();
}

test "widget_text_edit deleteLine" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.initFromFile(allocator, "tests/sample_4");
    var widget = try WidgetTextEdit.initWithBuffer(allocator, buffer);
    defer widget.deinit();

    try std.testing.expectEqual(400, widget.editor.buffer.linesCount());

    // delete the first line
    widget.deleteLine();
    try std.testing.expectEqual(399, widget.editor.buffer.linesCount());
    try std.testing.expectEqual(0, widget.cursor.pos.a);
    try std.testing.expectEqual(0, widget.cursor.pos.b);

    // delete a line in between

    widget.moveCursor(Vec2i{ .a = 5, .b = 15 }, true);
    try std.testing.expectEqual(5, widget.cursor.pos.a);
    try std.testing.expectEqual(15, widget.cursor.pos.b);
    widget.deleteLine();
    try std.testing.expectEqual(398, widget.editor.buffer.linesCount());
    try std.testing.expectEqual(5, widget.cursor.pos.a);
    try std.testing.expectEqual(15, widget.cursor.pos.b);

    // delete the very last line

    widget.moveCursor(Vec2i{ .a = 0, .b = @as(i64, @intCast(widget.editor.buffer.linesCount() + 100)) }, true);
    try std.testing.expectEqual(5, widget.cursor.pos.a);
    try std.testing.expectEqual(widget.editor.buffer.linesCount() - 1, widget.cursor.pos.b);
    widget.deleteLine();
    try std.testing.expectEqual(5, widget.cursor.pos.a);
    try std.testing.expectEqual(widget.editor.buffer.linesCount() - 1, widget.cursor.pos.b);
}

test "widget_text_edit onTab" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.initFromFile(allocator, "tests/sample_4");
    var widget = try WidgetTextEdit.initWithBuffer(allocator, buffer);
    defer widget.deinit();

    var line0 = try buffer.getLine(0);
    var line1 = try buffer.getLine(1);
    var line2 = try buffer.getLine(2);
    try std.testing.expectEqualSlices(u8, "test", line0.data.items[0..4]);
    try std.testing.expectEqualSlices(u8, "DjNb", line1.data.items[0..4]);
    try std.testing.expectEqualSlices(u8, "PkhI", line2.data.items[0..4]);

    widget.startSelection(Vec2u{ .a = 0, .b = 0 }, .KeyboardSelection);
    widget.moveCursor(Vec2i{ .a = 0, .b = 1 }, false);
    widget.moveCursor(Vec2i{ .a = 0, .b = 1 }, false);
    widget.onTab(false);

    try std.testing.expectEqualSlices(u8, "    test", line0.data.items[0..8]);
    try std.testing.expectEqualSlices(u8, "    DjNb", line1.data.items[0..8]);
    try std.testing.expectEqualSlices(u8, "    PkhI", line2.data.items[0..8]);

    widget.moveCursor(Vec2i{ .a = 0, .b = -1 }, false);
    widget.onTab(false);
    try std.testing.expectEqualSlices(u8, "        test", line0.data.items[0..12]);
    try std.testing.expectEqualSlices(u8, "        DjNb", line1.data.items[0..12]);
    try std.testing.expectEqualSlices(u8, "    PkhI", line2.data.items[0..8]);

    widget.moveCursor(Vec2i{ .a = 0, .b = 1 }, false);
    widget.onTab(true);
    try std.testing.expectEqualSlices(u8, "    test", line0.data.items[0..8]);
    try std.testing.expectEqualSlices(u8, "    DjNb", line1.data.items[0..8]);
    try std.testing.expectEqualSlices(u8, "PkhI", line2.data.items[0..4]);

    widget.onTab(true);
    try std.testing.expectEqualSlices(u8, "test", line0.data.items[0..4]);
    try std.testing.expectEqualSlices(u8, "DjNb", line1.data.items[0..4]);
    try std.testing.expectEqualSlices(u8, "PkhI", line2.data.items[0..4]);

    widget.stopSelection(.Inactive);
    widget.onTab(false);
    try std.testing.expectEqualSlices(u8, "test", line0.data.items[0..4]);
    try std.testing.expectEqualSlices(u8, "DjNb", line1.data.items[0..4]);
    try std.testing.expectEqualSlices(u8, "    PkhI", line2.data.items[0..8]);

    widget.onTab(true);
    try std.testing.expectEqualSlices(u8, "test", line0.data.items[0..4]);
    try std.testing.expectEqualSlices(u8, "DjNb", line1.data.items[0..4]);
    try std.testing.expectEqualSlices(u8, "PkhI", line2.data.items[0..4]);
}
