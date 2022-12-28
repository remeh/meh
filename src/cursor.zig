const std = @import("std");
const c = @import("clib.zig").c;

const Colors = @import("colors.zig");
const Draw = @import("draw.zig").Draw;
const InputMode = @import("widget_text_edit.zig").InputMode;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const char_tab = @import("u8slice.zig").char_tab;
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;
const Vec2u = @import("vec.zig").Vec2u;
const itou = @import("vec.zig").itou;
const utoi = @import("vec.zig").utoi;
const WidgetTextEdit = @import("widget_text_edit.zig").WidgetTextEdit;
const WidgetTextEditViewport = @import("widget_text_edit.zig").WidgetTextEditViewport;

/// Cursor represents the editing position in the WidgetTextEdit.
/// Its position is in glyph.
/// It is not tab-aware.
pub const Cursor = struct {
    /// pos is the position in glyph.
    /// Use UTF8Iterator if you need help moving in a line per glyph.
    pos: Vec2u,
    /// last_col_pos is used to remember last column max position to re-use
    /// it while moving up / down in lines.
    max_last_col_pos: usize,

    // Constructors
    // ------------

    pub fn init() Cursor {
        return Cursor{
            .pos = Vec2u{ .a = 0, .b = 0 },
            .max_last_col_pos = 0,
        };
    }

    // Methods
    // -------

    /// `render` renders the cursor in the `WidgetTextEdit`.
    /// `line_offset_in_buffer` contains the first visible line (of the buffer) in the current window. With this + the position
    /// of the cursor in the buffer, we can compute where to relatively position the cursor in the window in order to draw it.
    // TODO(remy): consider redrawing the character which is under the cursor in a reverse color to see it above the cursor
    pub fn render(_: Cursor, sdl_renderer: *c.SDL_Renderer, input_mode: InputMode, scaler: Scaler, draw_pos: Vec2u, one_char_size: Vec2u, focused: bool) void {
        var color = Colors.white;
        color.d = 180;

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
            .d, .f => {
                Draw.rect(
                    sdl_renderer,
                    scaler,
                    Vec2u{ .a = draw_pos.a, .b = draw_pos.b + (one_char_size.b - 2) },
                    Vec2u{ .a = one_char_size.a, .b = 2 },
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
                    color,
                );
            },
        }
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn posFromWindowPos(_: Cursor, text_edit: *WidgetTextEdit, click_window_pos: Vec2u, draw_pos: Vec2u) Vec2u {
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

                // happens when there is no content yet the last line of buffer
                if (last_line.size() > 0) {
                    rv.a = last_line.size() - 1;
                } else {
                    rv.a = 0;
                }
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

        // if the click is done after the line end, just move the cursor
        // to the line end.
        if (in_editor.a > move_done) {
            rv.a = utf8size;
            return rv;
        }

        return rv;
    }

    /// isVisible returns true if the cursor is visible in the given viewport.
    pub fn isVisible(self: Cursor, viewport: WidgetTextEditViewport) bool {
        return (self.pos.b >= viewport.lines.a and self.pos.b <= viewport.lines.b and
            self.pos.a >= viewport.columns.a and self.pos.a <= viewport.columns.b);
    }
};
