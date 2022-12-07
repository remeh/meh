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
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;
const WidgetInput = @import("widget_input.zig").WidgetInput;
const Insert = @import("widget_text_edit.zig").Insert;

pub const WidgetListEntryType = enum { File, Directory };

/// Entry is an entry in the WidgetList.
/// `filename` and `fullpath` are owned by the WidgetListEntry, use `deinit()` to release
/// their memory.
pub const WidgetListEntry = struct {
    label: U8Slice,
    data: U8Slice,
    type: WidgetListEntryType,

    pub fn deinit(self: *WidgetListEntry) void {
        self.label.deinit();
        self.data.deinit();
    }
};

pub const WidgetList = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(WidgetListEntry),
    /// Slices in `filtered_entries` are pointing to values in `entries`, they
    /// should not be freed.
    filtered_entries: std.ArrayList(WidgetListEntry),
    input: WidgetInput,
    label: U8Slice,
    selected_entry_idx: usize,
    visible_offset: usize,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetList {
        return WidgetList{
            .allocator = allocator,
            .entries = std.ArrayList(WidgetListEntry).init(allocator),
            .filtered_entries = std.ArrayList(WidgetListEntry).init(allocator),
            .input = try WidgetInput.init(allocator),
            .label = U8Slice.initEmpty(allocator),
            .selected_entry_idx = 0,
            .visible_offset = 0,
        };
    }

    pub fn deinit(self: *WidgetList) void {
        self.input.deinit();
        self.deleteEntries();
        self.entries.deinit();
        self.filtered_entries.deinit();
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
        self.entries.shrinkAndFree(0);
        self.filtered_entries.shrinkAndFree(0);
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
        self.visible_offset = 0;
        self.label.data.shrinkAndFree(0);
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
        self.visible_offset = 0;
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

    /// filter filters the `entries` list using what's available in the `input`.
    /// Slices in `filtered_entries` are pointing to values in `entries`.
    pub fn filter(self: *WidgetList) !void {
        self.filtered_entries.shrinkAndFree(0);
        var entered_filter = (try self.input.text()).bytes();
        for (self.entries.items) |entry| {
            var add = (entered_filter.len == 0);
            if (entered_filter.len > 0) {
                if (std.mem.containsAtLeast(u8, entry.label.bytes(), 1, entered_filter)) {
                    add = true;
                }
            }
            if (add) {
                try self.filtered_entries.append(entry);
            }
        }
        self.selected_entry_idx = 0;
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
        // input
        var input_pos = Vec2u{ .a = position.a + 5, .b = position.b + 5 };
        var input_size = Vec2u{ .a = widget_size.a, .b = 50 };

        self.input.render(sdl_renderer, font, scaler, input_pos, input_size, one_char_size);

        // label below the input / above the list

        var label_pos = Vec2u{ .a = position.a, .b = position.b + (one_char_size.b * 2) };
        Draw.text(font, scaler, label_pos, Colors.white, self.label.bytes());

        // list the entries
        // TODO(remy): only list visibles + scroll

        const sep_margin = 8;
        var offset: usize = 0;
        var idx: usize = 0;
        for (self.filtered_entries.items) |entry| {
            var pos = Vec2u{ .a = position.a, .b = position.b + 50 + one_char_size.b + sep_margin + offset };
            var size = Vec2u{ .a = widget_size.a, .b = one_char_size.b + sep_margin };

            self.renderEntry(
                sdl_renderer,
                font,
                scaler,
                pos,
                size,
                entry,
                idx == self.selected_entry_idx,
            );
            offset += one_char_size.b + sep_margin;
            idx += 1;
        }
    }

    pub fn renderEntry(
        _: *WidgetList,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        position: Vec2u,
        size: Vec2u,
        entry: WidgetListEntry,
        selected: bool,
    ) void {
        // TODO(remy): render an icon or such

        if (selected) {
            Draw.rect(sdl_renderer, scaler, position, size, Colors.white);
        }

        Draw.text(font, scaler, Vec2u{ .a = position.a + 5, .b = position.b + 3 }, Colors.white, entry.label.bytes());
    }

    pub fn sortEntriesByLabel(self: *WidgetList) void {
        std.sort.sort(WidgetListEntry, self.entries.items, {}, WidgetList.sortByLabel);
    }

    pub fn sortEntriesByData(self: *WidgetList) void {
        std.sort.sort(WidgetListEntry, self.entries.items, {}, WidgetList.sortByData);
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
