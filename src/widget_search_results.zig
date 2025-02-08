const std = @import("std");
const c = @import("clib.zig").c;

const App = @import("app.zig").App;
const Colors = @import("colors.zig");
const Draw = @import("draw.zig").Draw;
const FdResults = @import("fd.zig").FdResults;
const Font = @import("font.zig").Font;
const LSPPosition = @import("lsp.zig").LSPPosition;
const RipgrepResults = @import("ripgrep.zig").RipgrepResults;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const utoi = @import("vec.zig").utoi;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;
const WidgetInput = @import("widget_input.zig").WidgetInput;
const WidgetList = @import("widget_list.zig").WidgetList;
const WidgetListEntry = @import("widget_list.zig").WidgetListEntry;
const WidgetListEntryType = @import("widget_list.zig").WidgetListEntryType;
const WidgetListFilterType = @import("widget_list.zig").WidgetListFilterType;

const peekLine = @import("buffer.zig").peekLine;

pub const WidgetSearchResults = struct {
    allocator: std.mem.Allocator,
    displayed_search: U8Slice,
    list: WidgetList,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetSearchResults {
        return WidgetSearchResults{
            .allocator = allocator,
            .displayed_search = U8Slice.initEmpty(allocator),
            .list = try WidgetList.init(allocator, WidgetListFilterType.LabelAndData),
        };
    }

    pub fn deinit(self: *WidgetSearchResults) void {
        self.list.deinit();
        self.displayed_search.deinit();
    }

    // Methods
    // -------

    pub fn reset(self: *WidgetSearchResults) void {
        self.list.reset();
        self.results.deinit();
    }

    /// setDisplayedSearch clones `search` and doesn't managed the given one.
    pub fn setDisplayedSearch(self: *WidgetSearchResults, search: U8Slice) !void {
        self.displayed_search.deinit();
        self.displayed_search = try search.copy(self.allocator);
        // remove all entries
        self.list.deleteEntries();
    }

    /// select returns the selected Entry if any.
    /// It's *not* caller responsibility to free the Entry object.
    pub fn select(self: *WidgetSearchResults) !?WidgetListEntry {
        if (try self.list.select()) |entry| {
            return entry;
        }
        return null;
    }

    /// setRipgrepResults creates all entries in the widget_list. The given `results` is now
    /// owned by the WidgetSearchResults, no needs to free its resources as we copy the
    /// values in the WidgetListEntries.
    pub fn setRipgrepResults(self: *WidgetSearchResults, results: RipgrepResults) !void {
        self.list.reset();

        var it = results.iterator(self.allocator);
        defer results.deinit();

        while (it.next()) |result| {
            // no need to free the data in result as it will be managed
            // by the WidgetListEntry.
            try self.list.entries.append(WidgetListEntry{
                .label = result.content,
                .data = result.filename,
                .data_pos = Vec2i{ .a = utoi(result.column) - 1, .b = utoi(result.line_number) - 1 },
                .extra_info = null,
                .type = .SearchResult,
            });
        }

        try self.list.label.appendConst("Found:");
        try self.list.filter();
    }

    /// setFdResults creates all entries in the widget_list. The given `results` is now
    /// owned by the WidgetSearchResults, no needs to free its resources as we copy the
    /// values in the WidgetListEntries.
    pub fn setFdResults(self: *WidgetSearchResults, results: FdResults) !void {
        self.list.reset();

        var it = results.iterator(self.allocator);
        defer results.deinit();

        while (it.next()) |result| {
            // no need to free the data in result as it will be managed
            // by the WidgetListEntry.
            try self.list.entries.append(WidgetListEntry{
                .label = result.filepath,
                .data = try result.filepath.copy(self.allocator),
                .data_pos = Vec2i{ .a = 0, .b = 0 },
                .extra_info = null,
                .type = .File,
            });
        }

        try self.list.label.appendConst("Found:");
        try self.list.filter();
    }

    /// setLspReferences creates all entries in the widget list using LSPPositions data.
    /// The given `references` are _NOT_ owned by the WidgetSearchResults (copies are created).
    pub fn setLspReferences(self: *WidgetSearchResults, app: *App, references: std.ArrayList(LSPPosition)) !void {
        self.list.reset();

        for (references.items) |reference| {
            const line = try app.peekLine(reference.filepath.bytes(), reference.start.b);
            const pos = Vec2i{ .a = utoi(reference.start.a), .b = utoi(reference.start.b) };
            try self.list.entries.append(WidgetListEntry{
                .label = line,
                .data = try U8Slice.initFromSlice(self.allocator, reference.filepath.bytes()),
                .data_pos = pos,
                .extra_info = null,
                .type = .SearchResult,
            });
        }

        try self.list.label.appendConst("References found:");
        try self.list.filter();
    }

    pub fn render(
        self: *WidgetSearchResults,
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

test "WidgetSearchResults init/deinit" {
    // track leaks
    var rv = try WidgetSearchResults.init(std.testing.allocator);
    rv.deinit();
}
