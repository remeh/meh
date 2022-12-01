const std = @import("std");
const c = @import("clib.zig").c;

const Colors = @import("colors.zig");
const Draw = @import("draw.zig").Draw;
const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;
const WidgetInput = @import("widget_input.zig").WidgetInput;
const WidgetTextEdit = @import("widget_text_edit.zig").WidgetTextEdit;

const EntryType = enum { File, Directory };

const WidgetLookupMode = enum { OpenFile };

/// Entry is an entry in the files lookup widget.
/// `filename` and `fullpath` are owned by the Entry, use `deinit()` to release
/// their memory.
const Entry = struct {
    filename: U8Slice,
    fullpath: U8Slice,
    type: EntryType,

    pub fn deinit(self: *Entry) void {
        self.filename.deinit();
        self.fullpath.deinit();
    }
};

pub const WidgetLookup = struct {
    allocator: std.mem.Allocator,
    current_path: U8Slice,
    entries: std.ArrayList(Entry),
    /// Slices in `filtered_entries` are pointing to values in `entries`, they
    /// should not be freed.
    filtered_entries: std.ArrayList(Entry),
    input: WidgetInput,
    mode: WidgetLookupMode,
    selected_entry_idx: usize,
    visible_offset: usize,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetLookup {
        var current_path = U8Slice.initEmpty(allocator);
        try current_path.appendConst(".");

        return WidgetLookup{
            .allocator = allocator,
            .current_path = current_path,
            .entries = std.ArrayList(Entry).init(allocator),
            .filtered_entries = std.ArrayList(Entry).init(allocator),
            .input = try WidgetInput.init(allocator),
            .mode = WidgetLookupMode.OpenFile,
            .selected_entry_idx = 0,
            .visible_offset = 0,
        };
    }

    pub fn deinit(self: *WidgetLookup) void {
        self.input.deinit();
        self.current_path.deinit();
        self.deleteEntries();
        self.entries.deinit();
        self.filtered_entries.deinit();
    }

    // Events
    // ------

    pub fn onBackspace(self: *WidgetLookup) void {
        self.input.onBackspace();
        self.filter() catch |err| {
            std.log.err("WidgetLookup.onBackspace: can't filter after a backspace press: {} ", .{err});
        };
    }

    pub fn onTextInput(self: *WidgetLookup, txt: []const u8) void {
        self.input.onTextInput(txt);
        self.filter() catch |err| {
            std.log.err("WidgetLookup.onTextInput: can't filter after an input: {} ", .{err});
        };
    }

    // Methods
    // -------

    pub fn reset(self: *WidgetLookup) void {
        self.input.reset();
        self.deleteEntries();
        self.selected_entry_idx = 0;
        self.visible_offset = 0;
    }

    /// deleteEntries empties the entry list. (frees all the memory)
    pub fn deleteEntries(self: *WidgetLookup) void {
        var i: usize = 0;
        while (i < self.entries.items.len) {
            self.entries.items[i].deinit();
            i += 1;
        }
        self.entries.shrinkAndFree(0);
        self.filtered_entries.shrinkAndFree(0);
    }

    /// The given `filepath` isn't owned by the WidgetLookup (a copy is created
    /// because it will modify it).
    pub fn setFilepath(self: *WidgetLookup, filepath: U8Slice) !void {
        self.current_path.deinit();
        self.current_path = try U8Slice.initFromSlice(self.allocator, filepath.bytes());

        self.mode = WidgetLookupMode.OpenFile;

        // remove all entries
        self.deleteEntries();
    }

    /// select returns the selected Entry if any.
    /// It's *not* caller responsibility to free the Entry object.
    pub fn select(self: *WidgetLookup) !?Entry {
        if (self.filtered_entries.items.len == 0) {
            return null;
        }

        if (self.selected_entry_idx > self.filtered_entries.items.len) {
            return null;
        }

        var entry = self.filtered_entries.items[self.selected_entry_idx];

        if (entry.type == .Directory) {
            // build the next path
            try self.current_path.appendConst("/");
            try self.current_path.appendSlice(entry.filename);
            // make sure it is absolute
            var fullpath = try std.fs.realpathAlloc(self.allocator, self.current_path.bytes());
            defer self.allocator.free(fullpath);
            self.current_path.deinit();
            // store it as the fullpath
            self.current_path = U8Slice.initEmpty(self.allocator);
            try self.current_path.appendConst(fullpath);

            self.reset();
            try self.scanDir();
            try self.filter();
            return null;
        } else {
            return entry;
        }
    }

    /// scanDir lists all files in the `current_path` and create an Entry for each of them
    /// to be displayed in the WidgetLookup.
    // TODO(remy): unit test (list the dir "tests" and validate that files are present as Entry + no leaks)
    pub fn scanDir(self: *WidgetLookup) !void {
        self.reset();

        try self.entries.append(Entry{
            .filename = try U8Slice.initFromSlice(self.allocator, ".."),
            .fullpath = try U8Slice.initFromSlice(self.allocator, ".."),
            .type = .Directory,
        });

        var dir = try std.fs.cwd().openIterableDir(self.current_path.bytes(), std.fs.Dir.OpenDirOptions{ .access_sub_paths = false });
        defer dir.close();
        var it = dir.iterate();
        while (try it.next()) |entry| {
            switch (entry.kind) {
                .File, .Directory => {
                    var t = EntryType.File;
                    if (entry.kind == .Directory) {
                        t = EntryType.Directory;
                    }

                    var fullpath = U8Slice.initEmpty(self.allocator);
                    try fullpath.appendConst(self.current_path.bytes());
                    try fullpath.appendConst("/");
                    try fullpath.appendConst(entry.name);
                    try self.entries.append(Entry{
                        .filename = try U8Slice.initFromSlice(self.allocator, entry.name),
                        .fullpath = fullpath,
                        .type = t,
                    });
                },
                else => continue,
            }
        }

        std.sort.sort(Entry, self.entries.items, {}, WidgetLookup.sortByFullpath);
    }

    // TODO(remy): comment
    pub fn setTextEdits(self: *WidgetLookup, textedits: std.ArrayList(WidgetTextEdit)) !void {
        self.reset();
        for (textedits.items) |textedit| {
            try self.entries.append(Entry{
                .filename = try U8Slice.initFromSlice(self.allocator, textedit.editor.buffer.fullpath.bytes()),
                .fullpath = try U8Slice.initFromSlice(self.allocator, textedit.editor.buffer.fullpath.bytes()),
                .type = .File,
            });
        }
    }

    pub fn next(self: *WidgetLookup) void {
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

    pub fn previous(self: *WidgetLookup) void {
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
    pub fn filter(self: *WidgetLookup) !void {
        self.filtered_entries.shrinkAndFree(0);
        var entered_filter = (try self.input.text()).bytes();
        for (self.entries.items) |entry| {
            var add = (entered_filter.len == 0);
            if (entered_filter.len > 0) {
                if (std.mem.containsAtLeast(u8, entry.filename.bytes(), 1, entered_filter)) {
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
        self: *WidgetLookup,
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

        // input

        var input_pos = Vec2u{ .a = position.a + 5, .b = position.b + 5 };
        var input_size = Vec2u{ .a = widget_size.a, .b = 50 };

        self.input.render(sdl_renderer, font, scaler, input_pos, input_size, one_char_size);

        // render the current filepath

        var filepath_pos = Vec2u{ .a = position.a, .b = position.b + (one_char_size.b * 2) };
        Draw.text(font, scaler, filepath_pos, Colors.white, self.current_path.bytes());

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
        _: *WidgetLookup,
        sdl_renderer: *c.SDL_Renderer,
        font: Font,
        scaler: Scaler,
        position: Vec2u,
        size: Vec2u,
        entry: Entry,
        selected: bool,
    ) void {
        // TODO(remy): render an icon or such

        if (selected) {
            Draw.rect(sdl_renderer, scaler, position, size, Colors.white);
        }

        Draw.text(font, scaler, Vec2u{ .a = position.a + 5, .b = position.b + 3 }, Colors.white, entry.filename.bytes());
    }

    fn sortByFullpath(context: void, a: Entry, b: Entry) bool {
        _ = context;
        return std.mem.lessThan(u8, a.fullpath.bytes(), b.fullpath.bytes());
    }
};

test "WidgetInput init/deinit" {
    var rv = try WidgetInput.init(std.testing.allocator);
    rv.deinit();
}
