const std = @import("std");
const c = @import("clib.zig").c;

const Colors = @import("colors.zig");
const Draw = @import("draw.zig").Draw;
const Font = @import("font.zig").Font;
const RipgrepResults = @import("ripgrep.zig").RipgrepResults;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;
const WidgetInput = @import("widget_input.zig").WidgetInput;
const WidgetList = @import("widget_list.zig").WidgetList;
const WidgetListEntry = @import("widget_list.zig").WidgetListEntry;
const WidgetListEntryType = @import("widget_list.zig").WidgetListEntryType;
const WidgetListFilterType = @import("widget_list.zig").WidgetListFilterType;

pub const WidgetRipgrep = struct {
    allocator: std.mem.Allocator,
    displayed_search: U8Slice,
    list: WidgetList,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetRipgrep {
        return WidgetRipgrep{
            .allocator = allocator,
            .displayed_search = U8Slice.initEmpty(allocator),
            .list = try WidgetList.init(allocator, WidgetListFilterType.LabelAndData),
        };
    }

    pub fn deinit(self: *WidgetRipgrep) void {
        self.list.deinit();
        self.displayed_search.deinit();
    }

    // Methods
    // -------

    pub fn reset(self: *WidgetRipgrep) void {
        self.list.reset();
        self.results.deinit();
    }

    /// setDisplayedSearch clones `search` and doesn't managed the given one.
    pub fn setDisplayedSearch(self: *WidgetRipgrep, search: U8Slice) !void {
        self.displayed_search.deinit();
        self.displayed_search = try search.copy(self.allocator);
        // remove all entries
        self.list.deleteEntries();
    }

    /// select returns the selected Entry if any.
    /// It's *not* caller responsibility to free the Entry object.
    pub fn select(self: *WidgetRipgrep) !?WidgetListEntry {
        if (try self.list.select()) |entry| {
            return entry;
        }
        return null;
    }

    /// setResults creates all entries in the widget_list. The given `results` is not
    /// owned by the WidgetRipgrep, no needs to free its resources as we copy the
    /// values in the WidgetListEntries.
    pub fn setResults(self: *WidgetRipgrep, results: RipgrepResults) !void {
        self.list.reset();

        var it = results.iterator(self.allocator);
        defer results.deinit();

        while (it.next()) |result| {
            // no need to free the data in result as it will be managed
            // by the WidgetListEntry.
            try self.list.entries.append(WidgetListEntry{
                .label = result.content,
                .data = result.filename,
                .data_int = @intCast(i64, result.line_number),
                .type = .Ripgrep,
            });
        }

        try self.list.filter();
    }

    pub fn render(
        self: *WidgetRipgrep,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        window_scaled_size: Vec2u,
        position: Vec2u,
        widget_size: Vec2u,
        one_char_size: Vec2u,
    ) void {
        // overlay and background

        Draw.fillRect(sdl_renderer, scaler, Vec2u{ .a = 0, .b = 0 }, window_scaled_size, Vec4u{ .a = 20, .b = 20, .c = 20, .d = 130 });
        Draw.fillRect(sdl_renderer, scaler, position, widget_size, Vec4u{ .a = 20, .b = 20, .c = 20, .d = 230 });

        // list widget

        self.list.render(
            sdl_renderer,
            font,
            scaler,
            position,
            widget_size,
            one_char_size,
        );
    }
};

test "WidgetRipgrep init/deinit" {
    // track leaks
    var rv = try WidgetRipgrep.init(std.testing.allocator);
    rv.deinit();
}
