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
const WidgetMessageBox = @import("widget_messagebox.zig").WidgetMessageBox;

const ScreenSection = enum {
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
};

pub const WidgetAutocomplete = struct {
    allocator: std.mem.Allocator,
    filter_size: usize,
    no_results: bool,
    loading: bool,
    list: WidgetList,
    mbox: WidgetMessageBox,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetAutocomplete {
        return WidgetAutocomplete{
            .allocator = allocator,
            .filter_size = 0,
            .no_results = false,
            .loading = true,
            .list = try WidgetList.init(allocator, WidgetListFilterType.Autocomplete),
            .mbox = WidgetMessageBox.init(allocator),
        };
    }

    pub fn deinit(self: *WidgetAutocomplete) void {
        self.list.deinit();
        self.mbox.deinit();
    }

    // Methods
    // -------

    pub fn reset(self: *WidgetAutocomplete) void {
        self.list.reset();
        self.loading = true;
        self.no_results = false;
    }

    /// select returns the selected Entry if any.
    /// It's *not* caller responsibility to free the Entry object.
    pub fn select(self: *WidgetAutocomplete) !?WidgetListEntry {
        if (try self.list.select()) |entry| {
            return entry;
        }
        return null;
    }

    pub fn setCompletionItems(self: *WidgetAutocomplete, completions: std.ArrayList(LSPCompletion)) !void {
        self.list.reset();
        for (completions.items) |completion| {
            var extra_info = std.ArrayList(U8Slice).init(self.allocator);
            try extra_info.append(try completion.detail.copy(self.allocator));

            if (completion.documentation.size() > 0) {
                var it = std.mem.splitScalar(u8, completion.documentation.bytes(), '\n');
                var line = it.first();
                while (line.len > 0) {
                    const slice = try U8Slice.initFromSlice(self.allocator, line);
                    try extra_info.append(slice);
                    if (it.next()) |data| {
                        line = data;
                    } else {
                        break;
                    }
                }
            }

            try self.list.entries.append(WidgetListEntry{
                .label = try completion.label.copy(self.allocator),
                .data = try completion.insert_text.copy(self.allocator),
                .extra_info = extra_info,
                .data_pos = Vec2i{ .a = 0, .b = 0 }, // unused // TODO(remy): store Kind?
                .data_range = completion.range,
                .type = .Autocomplete,
            });
        }

        if (completions.items.len == 0) {
            self.setNoResults();
        }

        self.loading = false;
        try self.list.filter();
    }

    pub fn setNoResults(self: *WidgetAutocomplete) void {
        self.loading = false;
        self.no_results = true;
    }

    pub fn render(
        self: *WidgetAutocomplete,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        window_scaled_size: Vec2u,
        cursor_pixel_pos: Vec2u,
        one_char_size: Vec2u,
    ) void {
        // check in which part of the screen the cursor is currently at,
        // with this information, decide where to draw the autocomplete
        const third_window_scaled_size = Vec2u{
            .a = @divTrunc(window_scaled_size.a, 3),
            .b = @divTrunc(window_scaled_size.b, 3),
        };

        var section = ScreenSection.TopLeft;
        if (cursor_pixel_pos.a < third_window_scaled_size.a * 2 and cursor_pixel_pos.b < third_window_scaled_size.b * 2) {
            section = .TopLeft;
        } else if (cursor_pixel_pos.a < third_window_scaled_size.a * 2 and cursor_pixel_pos.b >= third_window_scaled_size.b * 2) {
            section = .BottomLeft;
        } else if (cursor_pixel_pos.a > third_window_scaled_size.a * 2 and cursor_pixel_pos.b < third_window_scaled_size.b * 2) {
            section = .TopRight;
        } else if (cursor_pixel_pos.a > third_window_scaled_size.a * 2 and cursor_pixel_pos.b >= third_window_scaled_size.b * 2) {
            section = .BottomRight;
        }

        // background
        const size = Vec2u{ .a = window_scaled_size.a / 3, .b = one_char_size.b * 20 };
        const top_left = switch (section) {
            .TopLeft => Vec2u{ .a = cursor_pixel_pos.a + one_char_size.a, .b = cursor_pixel_pos.b + one_char_size.b },
            .BottomLeft => Vec2u{ .a = cursor_pixel_pos.a + one_char_size.a, .b = cursor_pixel_pos.b - size.b + (one_char_size.b * 2) },
            .TopRight => Vec2u{ .a = cursor_pixel_pos.a - size.a, .b = cursor_pixel_pos.b + one_char_size.b },
            .BottomRight => Vec2u{ .a = cursor_pixel_pos.a - size.a, .b = cursor_pixel_pos.b + one_char_size.b - size.b },
        };
        Draw.fillRect(sdl_renderer, scaler, top_left, size, Colors.dark_gray);

        if (self.loading or self.no_results) {
            const text_start = Vec2u{
                .a = top_left.a + (size.a / 2) - one_char_size.a * 6,
                .b = top_left.b + (size.b / 2),
            };

            if (self.loading) {
                Draw.text(font, scaler, text_start, 0, Colors.white, "Loading...");
            } else {
                Draw.text(font, scaler, text_start, 0, Colors.white, "No results.");
            }
            return;
        }

        if (self.list.filtered_entries.items.len > 0) {
            const entry = self.list.filtered_entries.items[self.list.selected_entry_idx];
            if (entry.extra_info) |extra_info| {
                self.mbox.setMultiple(extra_info, .LSPMessage, .WithoutOverlay) catch |err| {
                    std.log.debug("can't set WidgetAutoComplete message box label: {any}", .{err});
                };
                self.mbox.render(sdl_renderer, font, scaler, window_scaled_size, one_char_size);
            }
        }

        self.list.render(
            sdl_renderer,
            font,
            scaler,
            top_left,
            size,
            one_char_size,
        );
    }
};

test "WidgetAutocomplete init/deinit" {
    // track leaks
    var rv = try WidgetAutocomplete.init(std.testing.allocator);
    rv.deinit();
}
