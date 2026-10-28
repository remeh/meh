const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const Colors = @import("colors.zig");
const Draw = @import("draw.zig").Draw;
const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const syntax_highlighter = @import("syntax_highlighter.zig");
const SyntaxHighlighter = syntax_highlighter.SyntaxHighlighter;
const U8Slice = @import("u8slice.zig").U8Slice;
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;

pub const WidgetMessageBoxType = enum {
    ExecOutput,
    LSPDiagnostic,
    LSPHover,
    LSPMessage,
    Error,
    Confirm,
};

pub const WidgetMessageBoxOverlay = enum {
    WithOverlay,
    WithoutOverlay,
};

/// Ink describes how the lines of the box are drawn:
///  - `syntax` is true when the content is code, and thus gets the same highlighting
///    as the editor does;
///  - `base` is the color of everything the syntax highlighter doesn't recognize.
const Ink = struct {
    syntax: bool,
    base: Vec4u,
};

pub const WidgetMessageBox = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(U8Slice),
    message: WidgetMessageBoxType,
    overlay: WidgetMessageBoxOverlay,
    x_offset: usize,
    y_offset: usize,
    keyword_matcher: std.StringHashMap(void),

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetMessageBox {
        var keyword_matcher = std.StringHashMap(void).init(allocator);
        for (syntax_highlighter.keywords) |keyword| {
            try keyword_matcher.put(keyword, {});
        }

        return WidgetMessageBox{
            .allocator = allocator,
            .lines = std.ArrayList(U8Slice).empty,
            .message = undefined,
            .overlay = .WithOverlay,
            .x_offset = 0,
            .y_offset = 0,
            .keyword_matcher = keyword_matcher,
        };
    }

    pub fn deinit(self: *WidgetMessageBox) void {
        self.resetLines();
        self.keyword_matcher.deinit();
    }

    // Methods
    // -------

    /// resetLines frees memory of all managed lines and empties the lines list.
    pub fn resetLines(self: *WidgetMessageBox) void {
        for (self.lines.items) |*item| {
            item.deinit();
        }
        self.lines.shrinkAndFree(self.allocator, 0);
    }

    /// set prepares the messagebox to display a single line.
    pub fn set(self: *WidgetMessageBox, line: []const u8, message: WidgetMessageBoxType, overlay: WidgetMessageBoxOverlay) !void {
        self.resetLines();
        const slice = try U8Slice.initFromSlice(self.allocator, line);
        try self.lines.append(self.allocator, slice);
        self.message = message;
        self.overlay = overlay;
        self.x_offset = 0;
        self.y_offset = 0;
    }

    /// append inserts a new line at the end.
    pub fn append(self: *WidgetMessageBox, line: []const u8) !void {
        const slice = try U8Slice.initFromSlice(self.allocator, line);
        try self.lines.append(self.allocator, slice);
    }

    /// setMultiple prepares the messagebox to display multiple lines.
    pub fn setMultiple(self: *WidgetMessageBox, lines: std.ArrayList(U8Slice), message: WidgetMessageBoxType, overlay: WidgetMessageBoxOverlay) !void {
        self.resetLines();
        for (lines.items) |line| {
            const copy = try line.copy(self.allocator);
            try self.lines.append(self.allocator, copy);
        }
        self.message = message;
        self.overlay = overlay;
        self.x_offset = 0;
        self.y_offset = 0;
    }

    /// messageInk returns how the current message has to be drawn.
    /// The LSP messages display code — signatures, types, quoted identifiers — so they
    /// all get highlighted, each keeping the color its type carries.
    fn messageInk(self: WidgetMessageBox) Ink {
        return switch (self.message) {
            // a diagnostic stays yellow, but the code it quotes stays highlighted.
            .LSPDiagnostic => Ink{ .syntax = true, .base = Colors.syntax_todo },
            // the hover and the completion's detail & documentation.
            .LSPHover, .LSPMessage => Ink{ .syntax = true, .base = Colors.ui_text_primary },
            // the shell output is not code.
            .ExecOutput => Ink{ .syntax = false, .base = Colors.ui_text_secondary },
            .Error, .Confirm => Ink{ .syntax = false, .base = Colors.ui_text_primary },
        };
    }

    fn renderSyntaxHighlighted(self: WidgetMessageBox, font: Font, scaler: Scaler, x: usize, y: usize, max_width: usize, base_color: Vec4u, text: []const u8) void {
        var content_slice = U8Slice.initEmpty(self.allocator);
        defer content_slice.deinit();
        content_slice.appendConst(text) catch {
            Draw.text(font, scaler, Vec2u{ .a = x, .b = y }, max_width, base_color, text);
            return;
        };

        var line_highlight = SyntaxHighlighter.compute(self.allocator, &content_slice, null, self.keyword_matcher) catch {
            Draw.text(font, scaler, Vec2u{ .a = x, .b = y }, max_width, base_color, text);
            return;
        };
        defer line_highlight.deinit();

        var it = UTF8Iterator.init(text, 0) catch {
            Draw.text(font, scaler, Vec2u{ .a = x, .b = y }, max_width, base_color, text);
            return;
        };

        const base_pos = scaler.Scale2u(Vec2u{ .a = x, .b = y });
        // the same advance as Draw.text, so a highlighted line is laid out exactly like
        // a plain one.
        const glyph_advance = font.font_size / 2;
        const max_width_pixels = scaler.Scaleu(max_width);
        var render_x: usize = 0;
        var has_more = true;

        while (has_more) {
            const g = it.glyph();
            if (g[0] == 0 or g[0] == '\n' or g[0] == '\r') {
                break;
            }

            if (g[0] == '\t') {
                render_x += font.font_size * 2;
            } else {
                const column_color = line_highlight.getForColumn(it.current_glyph);
                // whatever the highlighter didn't recognize takes the color of the message.
                const color = if (std.meta.eql(column_color, Colors.ui_text_primary)) base_color else column_color;
                font.drawGlyph(Vec2u{ .a = base_pos.a + render_x, .b = base_pos.b }, color, g);
                render_x += glyph_advance;
            }

            if (max_width > 0 and render_x >= max_width_pixels) {
                break;
            }

            has_more = it.next();
        }
    }

    /// render renders the messagebox on the given renderer.
    pub fn render(
        self: WidgetMessageBox,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        window_scaled_size: Vec2u,
        one_char_size: Vec2u, // one_char_size
    ) void {

        // overlay
        if (self.overlay == .WithOverlay) {
            Draw.fillRect(sdl_renderer, scaler, Vec2u{ .a = 0, .b = 0 }, window_scaled_size, Colors.ui_overlay);
        }

        const lines_to_draw = @min(10, self.lines.items.len);

        switch (self.message) {
            .ExecOutput, .LSPDiagnostic, .LSPHover, .LSPMessage => {
                const ink = self.messageInk();

                const lines_pixel_height: usize = lines_to_draw * (one_char_size.b + 1);
                const position = Vec2u{
                    .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.05)),
                    .b = window_scaled_size.b - lines_pixel_height - 50,
                };
                const size = Vec2u{
                    .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.9)),
                    .b = 30 + lines_pixel_height,
                };

                // Draw shadow
                Draw.fillRect(sdl_renderer, scaler, .{ .a = position.a + 6, .b = position.b + 6 }, size, Colors.ui_panel_shadow);

                // background and border
                Draw.fillRect(sdl_renderer, scaler, position, size, Colors.ui_surface);
                Draw.rect(sdl_renderer, scaler, position, size, Colors.ui_border_light);

                // content

                var y = position.b + 15;
                var i: usize = 0;
                for (self.lines.items) |line| {
                    if (self.y_offset > i) {
                        i += 1;
                        continue;
                    }
                    var text: []const u8 = ""; // TODO(remy): doesn't support utf8
                    if (self.x_offset < line.size()) {
                        text = line.bytes()[self.x_offset..];
                    }

                    if (ink.syntax and text.len > 0) {
                        self.renderSyntaxHighlighted(font, scaler, position.a + 15, y, size.a - 30, ink.base, text);
                    } else {
                        Draw.text(font, scaler, Vec2u{ .a = position.a + 15, .b = y }, size.a - 30, ink.base, text);
                    }

                    y += one_char_size.b + 1;
                    i += 1;
                    if (i > self.y_offset + 10) {
                        break;
                    }
                }
            },
            else => {
                const position = Vec2u{
                    .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.1)),
                    .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.b)) * 0.1)),
                };
                const size = Vec2u{
                    .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(window_scaled_size.a)) * 0.8)),
                    .b = 50,
                };

                // panel, floating above the editor
                Draw.fillRect(sdl_renderer, scaler, position, size, Colors.ui_surface);
                Draw.rect(sdl_renderer, scaler, position, size, Colors.ui_border_light);

                const line = self.lines.items[0];
                var text: []const u8 = ""; // TODO(remy): doesn't support utf8
                if (self.x_offset < line.size()) {
                    text = line.bytes()[self.x_offset..];
                }

                // content
                Draw.text(font, scaler, Vec2u{ .a = position.a + 15, .b = position.b + 15 }, size.a - 30, Colors.ui_text_primary, text);
            },
        }
    }
};

// the LSP boxes show code, so they are highlighted; each keeps the color its type
// carries, and what is not code stays plain.
test "widget_message_box ink" {
    const allocator = std.testing.allocator;
    var msgbox = try WidgetMessageBox.init(allocator);
    defer msgbox.deinit();

    try msgbox.set("fn cwd() Linux", .LSPHover, .WithOverlay);
    try expect(msgbox.messageInk().syntax);
    try std.testing.expectEqual(Colors.ui_text_primary, msgbox.messageInk().base);

    // the completion's detail & documentation
    try msgbox.set("fn cwd() Linux", .LSPMessage, .WithoutOverlay);
    try expect(msgbox.messageInk().syntax);
    try std.testing.expectEqual(Colors.ui_text_primary, msgbox.messageInk().base);

    // a diagnostic keeps its warning color
    try msgbox.set("unused variable: foo", .LSPDiagnostic, .WithOverlay);
    try expect(msgbox.messageInk().syntax);
    try std.testing.expectEqual(Colors.syntax_todo, msgbox.messageInk().base);

    // the shell output is not code
    try msgbox.set("make: *** no rule to make target", .ExecOutput, .WithOverlay);
    try expect(!msgbox.messageInk().syntax);
    try std.testing.expectEqual(Colors.ui_text_secondary, msgbox.messageInk().base);

    try msgbox.set("do you really want to quit?", .Confirm, .WithOverlay);
    try expect(!msgbox.messageInk().syntax);
    try std.testing.expectEqual(Colors.ui_text_primary, msgbox.messageInk().base);
}

test "widget_message_box main tests" {
    const allocator = std.testing.allocator;
    var msgbox = try WidgetMessageBox.init(allocator);
    defer msgbox.deinit();

    try msgbox.append("hello");
    try msgbox.append("world");
    try std.testing.expectEqual(2, msgbox.lines.items.len);
    try std.testing.expectEqualStrings("hello", msgbox.lines.items[0].bytes());
    try std.testing.expectEqualStrings("world", msgbox.lines.items[1].bytes());

    msgbox.resetLines();
    try msgbox.append("hello world");
    try std.testing.expectEqual(1, msgbox.lines.items.len);
    try std.testing.expectEqualStrings("hello world", msgbox.lines.items[0].bytes());

    try msgbox.append("second line");
    try std.testing.expectEqual(2, msgbox.lines.items.len);

    try msgbox.set("an lsp diagnostic", .LSPDiagnostic, .WithOverlay);
    try std.testing.expectEqual(1, msgbox.lines.items.len);
    try std.testing.expectEqualStrings("an lsp diagnostic", msgbox.lines.items[0].bytes());

    var lines = std.ArrayList(U8Slice).empty;
    try lines.append(allocator, try U8Slice.initFromSlice(allocator, "hello"));
    try lines.append(allocator, try U8Slice.initFromSlice(allocator, "world"));
    try msgbox.setMultiple(lines, .LSPDiagnostic, .WithOverlay);
    try std.testing.expectEqual(2, msgbox.lines.items.len);
    try std.testing.expectEqualStrings("hello", msgbox.lines.items[0].bytes());
    try std.testing.expectEqualStrings("world", msgbox.lines.items[1].bytes());

    for (lines.items) |line| {
        line.deinit();
    }
    lines.deinit(allocator);
}
