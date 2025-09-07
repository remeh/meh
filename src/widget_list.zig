const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const App = @import("app.zig").App;
const Buffer = @import("buffer.zig").Buffer;
const Colors = @import("colors.zig");
const Direction = @import("app.zig").Direction;
const Draw = @import("draw.zig").Draw;
const Editor = @import("editor.zig").Editor;
const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const SearchDirection = @import("editor.zig").SearchDirection;
const U8Slice = @import("u8slice.zig").U8Slice;
const UTF8Iterator = @import("u8slice.zig").UTF8Iterator;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;
const WidgetInput = @import("widget_input.zig").WidgetInput;
const Insert = @import("widget_text_edit.zig").Insert;

pub const WidgetListEntryType = enum {
    Autocomplete,
    Directory,
    File,
    SearchResult,
};

pub const WidgetListFilterType = enum {
    Autocomplete,
    Label,
    Data,
    LabelAndData,
};

/// Entry is an entry in the WidgetList.
pub const WidgetListEntry = struct {
    label: U8Slice,
    data: U8Slice,
    /// use this one if you need to display extra information in a message box
    extra_info: ?std.ArrayListUnmanaged(U8Slice),
    extra_info_allocator: ?std.mem.Allocator,
    data_pos: Vec2i,
    data_range: ?Vec4u = null,

    type: WidgetListEntryType,

    pub fn deinit(self: *WidgetListEntry) void {
        self.label.deinit();
        self.data.deinit();

        if (self.extra_info) |*extra| {
            for (extra.items) |*item| {
                item.deinit();
            }
            extra.deinit(self.extra_info_allocator.?);
        }
    }
};

const page_jump: usize = 15;

pub const WidgetList = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(WidgetListEntry),
    /// Slices in `filtered_entries` are pointing to values in `entries`, they
    /// should not be freed.
    filtered_entries: std.ArrayListUnmanaged(WidgetListEntry),
    filter_type: WidgetListFilterType,
    input: WidgetInput,
    label: U8Slice,
    selected_entry_idx: usize,
    // when moving left/right because of long lines, how many glyphs we should offset with
    x_offset: usize,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator, filter_type: WidgetListFilterType) !WidgetList {
        return WidgetList{
            .allocator = allocator,
            .entries = std.ArrayListUnmanaged(WidgetListEntry).empty,
            .filtered_entries = std.ArrayListUnmanaged(WidgetListEntry).empty,
            .filter_type = filter_type,
            .input = try WidgetInput.init(allocator),
            .label = U8Slice.initEmpty(allocator),
            .selected_entry_idx = 0,
            .x_offset = 0,
        };
    }

    pub fn deinit(self: *WidgetList) void {
        self.input.deinit();
        self.deleteEntries();
        self.entries.deinit(self.allocator);
        self.filtered_entries.deinit(self.allocator);
        self.label.deinit();
    }

    // Methods
    // -------

    /// deleteEntries empties the entry list. (frees all the memory)
    pub fn deleteEntries(self: *WidgetList) void {
        var i: usize = 0;
        while (i < self.entries.items.len) {
            self.entries.items[i].deinit();
            i += 1;
        }
        self.entries.shrinkAndFree(self.allocator, 0);
        self.filtered_entries.shrinkAndFree(self.allocator, 0);
    }

    /// select returns the selected WidgetListEntry if any.
    /// It's *not* caller responsibility to free the WidgetEntry memory.
    pub fn select(self: *WidgetList) !?WidgetListEntry {
        if (self.filtered_entries.items.len == 0) {
            return null;
        }

        if (self.selected_entry_idx > self.filtered_entries.items.len) {
            return null;
        }

        return self.filtered_entries.items[self.selected_entry_idx];
    }

    pub fn reset(self: *WidgetList) void {
        self.input.reset();
        self.deleteEntries();
        self.selected_entry_idx = 0;
        self.label.data.shrinkAndFree(self.label.allocator, 0);
        self.x_offset = 0;
    }

    pub fn next(self: *WidgetList) void {
        if (self.filtered_entries.items.len < 1) {
            return;
        }
        if (self.selected_entry_idx == self.filtered_entries.items.len - 1) {
            self.selected_entry_idx = 0;
        } else {
            self.selected_entry_idx += 1;
        }
    }

    pub fn previous(self: *WidgetList) void {
        if (self.filtered_entries.items.len < 1) {
            return;
        }

        if (self.selected_entry_idx == 0) {
            self.selected_entry_idx = self.filtered_entries.items.len - 1;
        } else {
            self.selected_entry_idx -= 1;
        }

        // TODO(remy): compute visible_offset
    }

    pub fn nextPage(self: *WidgetList) void {
        if (self.filtered_entries.items.len < 1) {
            return;
        }

        self.selected_entry_idx = @min(self.selected_entry_idx + page_jump, self.filtered_entries.items.len - 1);
    }

    pub fn previousPage(self: *WidgetList) void {
        if (self.filtered_entries.items.len < 1) {
            return;
        }

        if (self.selected_entry_idx < page_jump) {
            self.selected_entry_idx = 0;
        } else {
            self.selected_entry_idx -= page_jump;
        }
    }

    pub fn right(self: *WidgetList) void {
        self.x_offset += 1;
    }

    pub fn left(self: *WidgetList) void {
        if (self.x_offset > 0) {
            self.x_offset -= 1;
        }
    }

    /// filter filters the `entries` list using what's available in the `input`.
    /// Slices in `filtered_entries` are pointing to values in `entries`.
    pub fn filter(self: *WidgetList) !void {
        self.filtered_entries.shrinkAndFree(self.allocator, 0);
        const entered_filter = (try self.input.text()).bytes();
        for (self.entries.items) |entry| {
            var add = (entered_filter.len == 0);
            if (entered_filter.len > 0) {
                if ((self.filter_type == .Autocomplete or self.filter_type == .Label or self.filter_type == .LabelAndData) and
                    std.mem.containsAtLeast(u8, entry.label.bytes(), 1, entered_filter))
                {
                    add = true;
                }
                if ((self.filter_type == .Data or self.filter_type == .LabelAndData) and
                    std.mem.containsAtLeast(u8, entry.data.bytes(), 1, entered_filter))
                {
                    add = true;
                }
            }
            if (add) {
                try self.filtered_entries.append(self.allocator, entry);
            }
        }
        self.selected_entry_idx = 0;
        self.x_offset = 0;
    }

    pub fn render(
        self: *WidgetList,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        position: Vec2u,
        widget_size: Vec2u,
        one_char_size: Vec2u,
    ) void {
        const input_height: usize = switch (self.filter_type) {
            .Autocomplete => 0,
            else => 50,
        };
        const input_sep_margin: usize = switch (self.filter_type) {
            .Autocomplete => 0,
            else => 2,
        };
        const label_sep_margin: usize = switch (self.filter_type) {
            .Autocomplete => 0,
            else => one_char_size.b,
        };
        const entry_sep_margin = 2;

        // when reaching the bottom of the list, we want to start scrolling before
        // reaching the last entry.
        const start_scroll_bottom_offset = 3;

        // input
        // ----

        if (self.filter_type != .Autocomplete) {
            const input_pos = Vec2u{ .a = position.a + 5, .b = position.b + 5 };
            const input_size = Vec2u{ .a = widget_size.a, .b = input_height };

            self.input.render(sdl_renderer, font, scaler, input_pos, input_size, one_char_size);
        }

        // label below the input / above the list
        // ----

        if (self.filter_type != .Autocomplete) {
            const label_pos = Vec2u{ .a = position.a + one_char_size.a, .b = position.b + (one_char_size.b * 2) };
            Draw.text(font, scaler, label_pos, widget_size.a, Colors.white, self.label.bytes());
        }

        // list the entries
        // ----

        const visible_entries: usize = (widget_size.b - (input_height + entry_sep_margin)) / (one_char_size.b + input_sep_margin);
        var offset: usize = 0;
        var entry_offset: usize = 0;

        // offset what we're looking at if the selected entry would not be visible.
        if (self.filtered_entries.items.len >= visible_entries and (self.selected_entry_idx + start_scroll_bottom_offset) > visible_entries) {
            entry_offset = self.selected_entry_idx + 3 - visible_entries;
        }

        var idx: usize = entry_offset;
        while (idx < self.filtered_entries.items.len) {
            const entry = self.filtered_entries.items[idx];
            const pos = Vec2u{ .a = position.a, .b = position.b + input_height + label_sep_margin + entry_sep_margin + offset };
            const size = Vec2u{ .a = widget_size.a, .b = one_char_size.b + entry_sep_margin + 1 };

            self.renderEntry(
                sdl_renderer,
                font,
                scaler,
                pos,
                size,
                entry,
                idx == self.selected_entry_idx,
            );

            offset += one_char_size.b + input_sep_margin;
            idx += 1;

            // more entries won't fit, stop drawing them
            if ((idx + (start_scroll_bottom_offset - 1)) - entry_offset > visible_entries) {
                break;
            }
        }
    }

    pub fn renderEntry(
        self: *WidgetList,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        position: Vec2u,
        size: Vec2u,
        entry: WidgetListEntry,
        selected: bool,
    ) void {
        if (selected) {
            Draw.rect(sdl_renderer, scaler, Vec2u{ .a = position.a, .b = position.b + 2 }, size, Colors.white);
        }

        // maximum amount if visible glyph
        const total_visible_glyph_count = @divTrunc(scaler.Scaleu(size.a), @divTrunc(font.font_size, 2)) - 1;

        switch (entry.type) {
            .SearchResult => {
                const base = std.fs.path.basename(entry.data.bytes());
                const filename = std.fmt.allocPrint(self.allocator, "{s}:{d}  ", .{ base, entry.data_pos.b }) catch |err| {
                    std.log.err("WidgetList.renderEntry: can't create filename with line number string: {}", .{err});
                    return;
                };
                const filename_size = font.textPixelSize(scaler, filename);

                Draw.text(font, scaler, Vec2u{ .a = position.a + 5, .b = position.b + 3 }, size.a, Colors.white, filename);

                var content = entry.label.bytes();

                // compute what's the space left for the result content

                var content_visible_glyph_count: usize = 0;
                if (total_visible_glyph_count > filename.len) {
                    content_visible_glyph_count = total_visible_glyph_count - filename.len;
                } else {
                    std.log.warn("WidgetList.renderEntry: no space left to draw the content", .{});
                    return;
                }

                var it = UTF8Iterator.init(content, self.x_offset) catch |err| {
                    std.log.err("WidgetList.renderEntry: can't create an UTF8Iterator: {}", .{err});
                    return;
                };

                const start_bytes_offset = it.current_byte;
                var glyphs_count: usize = 0;

                while (glyphs_count <= content_visible_glyph_count and it.next()) {
                    glyphs_count += 1;
                }

                if (glyphs_count > 0) {
                    Draw.text(
                        font,
                        scaler,
                        Vec2u{ .a = position.a + 5 + filename_size, .b = position.b + 3 },
                        content_visible_glyph_count * font.font_size / 2,
                        Colors.white,
                        content[start_bytes_offset..it.current_byte],
                    );
                }

                self.allocator.free(filename);
            },
            else => {
                var content = entry.label.bytes();

                const it = UTF8Iterator.init(content, self.x_offset) catch |err| {
                    std.log.err("WidgetList.renderEntry: can't create an UTF8Iterator: {}", .{err});
                    return;
                };

                Draw.text(
                    font,
                    scaler,
                    Vec2u{ .a = position.a + 5, .b = position.b + 3 },
                    size.a,
                    Colors.white,
                    content[it.current_byte..],
                );
            },
        }
    }

    pub fn sortEntriesByLabel(self: *WidgetList) void {
        std.sort.insertion(WidgetListEntry, self.entries.items, {}, WidgetList.sortByLabel);
    }

    pub fn sortEntriesByData(self: *WidgetList) void {
        std.sort.insertion(WidgetListEntry, self.entries.items, {}, WidgetList.sortByData);
    }

    fn sortByData(context: void, a: WidgetListEntry, b: WidgetListEntry) bool {
        _ = context;
        return std.mem.lessThan(u8, a.data.bytes(), b.data.bytes());
    }

    fn sortByLabel(context: void, a: WidgetListEntry, b: WidgetListEntry) bool {
        _ = context;
        return std.mem.lessThan(u8, a.label.bytes(), b.label.bytes());
    }

    // Events
    // ------

    pub fn onBackspace(self: *WidgetList) void {
        self.input.onBackspace();
        self.filter() catch |err| {
            std.log.err("WidgetList.onBackspace: can't filter after a backspace press: {} ", .{err});
        };
    }

    pub fn onTextInput(self: *WidgetList, txt: []const u8) void {
        self.input.onTextInput(txt);
        self.filter() catch |err| {
            std.log.err("WidgetList.onTextInput: can't filter after an input: {} ", .{err});
        };
    }
};
