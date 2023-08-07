const std = @import("std");
const c = @import("clib.zig").c;

const App = @import("app.zig").App;
const Buffer = @import("buffer.zig").Buffer;
const Direction = @import("app.zig").Direction;
const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const WidgetTextEdit = @import("widget_text_edit.zig").WidgetTextEdit;
const Insert = @import("widget_text_edit.zig").Insert;

/// WidgetInput is a simple one line input field for user input.
pub const WidgetInput = struct {
    allocator: std.mem.Allocator,
    widget_text_edit: WidgetTextEdit,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetInput {
        var rv = WidgetInput{
            .allocator = allocator,
            .widget_text_edit = try WidgetTextEdit.initWithBuffer(allocator, try Buffer.initEmpty(allocator)),
        };

        rv.widget_text_edit.render_line_numbers = false;
        rv.widget_text_edit.editor.history_enabled = false;
        rv.widget_text_edit.viewport.lines.a = 0;
        rv.widget_text_edit.viewport.columns.a = 0;
        rv.widget_text_edit.setInputMode(.Insert);

        return rv;
    }

    pub fn deinit(self: *WidgetInput) void {
        self.widget_text_edit.deinit();
    }

    // Methods
    // -------

    /// reset resets the input field and its content.
    pub fn reset(self: *WidgetInput) void {
        self.widget_text_edit.editor.buffer.lines.items[0].deinit();
        self.widget_text_edit.editor.buffer.lines.items[0] = U8Slice.initEmpty(self.allocator);
        self.widget_text_edit.cursor.pos.a = 0;
        self.widget_text_edit.cursor.pos.b = 0;
    }

    /// onBackspace is called when the user presses backspace.
    pub fn onBackspace(self: *WidgetInput) void {
        self.widget_text_edit.editor.deleteGlyph(self.widget_text_edit.cursor.pos, .Left, .Input) catch |err| {
            std.log.err("WidgetInput: {}", .{err});
        };
        self.widget_text_edit.moveCursor(Vec2i{ .a = -1, .b = 0 }, true);
    }

    /// text returns the text wrote in the input.
    pub fn text(self: WidgetInput) !*U8Slice {
        return try self.widget_text_edit.editor.buffer.getLine(0);
    }

    /// onArrowKey is called when the user presses an arrow key.
    pub fn onArrowKey(self: *WidgetInput, direction: Direction) void {
        self.widget_text_edit.onArrowKey(direction);
    }

    /// onTextInput is called when the user is inputting text.
    pub fn onTextInput(self: *WidgetInput, txt: []const u8) void {
        _ = self.widget_text_edit.onTextInput(txt);
    }

    pub fn render(
        self: *WidgetInput,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        position: Vec2u,
        widget_size: Vec2u,
        one_char_size: Vec2u,
    ) void {
        self.widget_text_edit.viewport.lines.a = 0;
        self.widget_text_edit.viewport.lines.b = 1;
        _ = c.SDL_SetTextureColorMod(font.atlas.texture, 255, 255, 255);
        self.widget_text_edit.render(sdl_renderer, font, scaler, position, widget_size, one_char_size, true);
    }
};
