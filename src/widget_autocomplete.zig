const std = @import("std");
const c = @import("clib.zig").c;

const Colors = @import("colors.zig");
const Draw = @import("draw.zig").Draw;
const Font = @import("font.zig").Font;
const LSPCompletion = @import("lsp.zig").LSPCompletion;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const WidgetList = @import("widget_list.zig").WidgetList;
const WidgetListEntry = @import("widget_list.zig").WidgetListEntry;
const WidgetListEntryType = @import("widget_list.zig").WidgetListEntryType;
const WidgetListFilterType = @import("widget_list.zig").WidgetListFilterType;

const ScreenSection = enum {
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
};

pub const WidgetAutocomplete = struct {
    allocator: std.mem.Allocator,
    loading: bool,
    list: WidgetList,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetAutocomplete {
        return WidgetAutocomplete{
            .allocator = allocator,
            .loading = true,
            .list = try WidgetList.init(allocator, WidgetListFilterType.Label),
        };
    }

    pub fn deinit(self: *WidgetAutocomplete) void {
        self.list.deinit();
    }

    // Methods
    // -------

    pub fn reset(self: *WidgetAutocomplete) void {
        self.list.reset();
        self.loading = true;
        // TODO(remy): reset entries
    }

    /// select returns the selected Entry if any.
    /// It's *not* caller responsibility to free the Entry object.
    pub fn select(self: *WidgetAutocomplete) !?WidgetListEntry {
        if (try self.list.select()) |_| {
            // TODO(remy): insert text in the widget text edit
        }
        return null;
    }

    pub fn setCompletionItems(self: *WidgetAutocomplete, completions: std.ArrayList(LSPCompletion)) !void {
        self.list.reset();
        for (completions.items) |completion| {
            try self.list.entries.append(WidgetListEntry{
                .label = try completion.label.copy(self.allocator),
                .data = try completion.insert_text.copy(self.allocator),
                .data_pos = Vec2i{ .a = 0, .b = 0 }, // unused // TODO(remy): store Kind?
                .type = .Autocomplete,
            });
        }
        self.loading = false;
        try self.list.filter();
    }

    pub fn render(
        self: *WidgetAutocomplete,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        window_scaled_size: Vec2u,
        cursor_pixel_pos: Vec2u,
        widget_size: Vec2u,
        one_char_size: Vec2u,
    ) void {
        // check in which part of the screen the cursor is currently at,
        // with this information, decide where to draw the autocomplete
        var half_window_scaled_size = Vec2u{
            .a = @divTrunc(window_scaled_size.a, 2),
            .b = @divTrunc(window_scaled_size.b, 2),
        };

        var section = ScreenSection.TopLeft;
        if (cursor_pixel_pos.a < half_window_scaled_size.a and cursor_pixel_pos.b < half_window_scaled_size.b) {
            section = .TopLeft;
        } else if (cursor_pixel_pos.a < half_window_scaled_size.a and cursor_pixel_pos.b >= half_window_scaled_size.b) {
            section = .BottomLeft;
        } else if (cursor_pixel_pos.a > half_window_scaled_size.a and cursor_pixel_pos.b < half_window_scaled_size.b) {
            section = .TopRight;
        } else if (cursor_pixel_pos.a > half_window_scaled_size.a and cursor_pixel_pos.b >= half_window_scaled_size.b) {
            section = .BottomRight;
        }

        // background
        const size = Vec2u{ .a = window_scaled_size.a / 3, .b = one_char_size.b * 20 };
        const top_left = switch (section) {
            .TopLeft => Vec2u{ .a = cursor_pixel_pos.a + one_char_size.a, .b = cursor_pixel_pos.b + one_char_size.b },
            .BottomLeft => Vec2u{ .a = cursor_pixel_pos.a + one_char_size.a, .b = cursor_pixel_pos.b - size.b + one_char_size.b },
            .TopRight => Vec2u{ .a = cursor_pixel_pos.a - size.a, .b = cursor_pixel_pos.b },
            .BottomRight => Vec2u{ .a = cursor_pixel_pos.a - size.a, .b = cursor_pixel_pos.b - size.b },
        };
        Draw.fillRect(sdl_renderer, scaler, top_left, size, Colors.dark_gray);

        if (self.loading) {
            const text_start = Vec2u{
                .a = top_left.a + (size.a / 2) - one_char_size.a * 6,
                .b = top_left.b + (size.b / 2),
            };

            Draw.text(font, scaler, text_start, 0, Colors.white, "Loading...");
            return;
        }

        self.list.render(
            sdl_renderer,
            font,
            scaler,
            cursor_pixel_pos,
            widget_size,
            one_char_size,
        );
    }
};

test "WidgetAutocomplete init/deinit" {
    // track leaks
    var rv = try WidgetAutocomplete.init(std.testing.allocator);
    rv.deinit();
}
