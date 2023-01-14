const std = @import("std");
const c = @import("clib.zig").c;

const Colors = @import("colors.zig");
const Draw = @import("draw.zig").Draw;
const Font = @import("font.zig").Font;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;
const WidgetInput = @import("widget_input.zig").WidgetInput;
const WidgetList = @import("widget_list.zig").WidgetList;
const WidgetListEntry = @import("widget_list.zig").WidgetListEntry;
const WidgetListEntryType = @import("widget_list.zig").WidgetListEntryType;
const WidgetListFilterType = @import("widget_list.zig").WidgetListFilterType;
const WidgetTextEdit = @import("widget_text_edit.zig").WidgetTextEdit;

pub const WidgetLookup = struct {
    allocator: std.mem.Allocator,
    current_path: U8Slice,
    list: WidgetList,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !WidgetLookup {
        var current_path = U8Slice.initEmpty(allocator);
        try current_path.appendConst(".");

        return WidgetLookup{
            .allocator = allocator,
            .current_path = current_path,
            .list = try WidgetList.init(allocator, WidgetListFilterType.Label),
        };
    }

    pub fn deinit(self: *WidgetLookup) void {
        self.list.deinit();
        self.current_path.deinit();
    }

    // Methods
    // -------

    pub fn reset(self: *WidgetLookup) void {
        self.list.reset();
    }

    /// The given `filepath` isn't owned by the WidgetLookup, it creates a copy instead
    /// because it has to mutate it.
    pub fn setFilepath(self: *WidgetLookup, filepath: U8Slice) !void {
        self.current_path.deinit();
        self.current_path = try U8Slice.initFromSlice(self.allocator, filepath.bytes());
        // remove all entries
        self.list.deleteEntries();
    }

    /// select returns the selected Entry if any.
    /// It's *not* caller responsibility to free the Entry object.
    pub fn select(self: *WidgetLookup) !?WidgetListEntry {
        if (try self.list.select()) |entry| {
            if (entry.type == .Directory) {
                // build the next path
                try self.current_path.appendConst("/");
                try self.current_path.appendSlice(entry.label);
                // make sure it is absolute
                var fullpath = try std.fs.realpathAlloc(self.allocator, self.current_path.bytes());
                defer self.allocator.free(fullpath);
                self.current_path.deinit();
                // store it as the fullpath
                self.current_path = U8Slice.initEmpty(self.allocator);
                try self.current_path.appendConst(fullpath);

                self.reset();
                try self.scanDir();
                return null;
            } else {
                return entry;
            }
        }
        return null;
    }

    /// scanDir lists all files in the `current_path` and create an Entry for each of them
    /// to be displayed in the WidgetLookup.
    // TODO(remy): unit test (list the dir "tests" and validate that files are present as Entry + no leaks)
    pub fn scanDir(self: *WidgetLookup) !void {
        self.list.reset();

        try self.list.entries.append(WidgetListEntry{
            .label = try U8Slice.initFromSlice(self.allocator, ".."),
            .data = try U8Slice.initFromSlice(self.allocator, ".."),
            .data_pos = Vec2i{ .a = -1, .b = -1 }, // unused
            .type = .Directory,
        });

        var dir = try std.fs.cwd().openIterableDir(self.current_path.bytes(), std.fs.Dir.OpenDirOptions{ .access_sub_paths = false });
        defer dir.close();
        var it = dir.iterate();
        while (try it.next()) |entry| {
            switch (entry.kind) {
                .File, .Directory => {
                    var t: WidgetListEntryType = .File;
                    if (entry.kind == .Directory) {
                        t = .Directory;
                    }

                    var fullpath = U8Slice.initEmpty(self.allocator);
                    try fullpath.appendConst(self.current_path.bytes());
                    try fullpath.appendConst("/");
                    try fullpath.appendConst(entry.name);

                    var label = try U8Slice.initFromSlice(self.allocator, entry.name);
                    if (t == .Directory) {
                        try label.appendConst("/");
                    }

                    try self.list.entries.append(WidgetListEntry{
                        .label = label,
                        .data = fullpath,
                        .data_pos = Vec2i{ .a = -1, .b = -1 }, // unused
                        .type = t,
                    });
                },
                else => continue,
            }
        }

        self.list.sortEntriesByData();

        try self.list.label.appendSlice(self.current_path);

        try self.list.filter();
    }

    /// setTextEdits sets the opened WidgetTextEdit for the WidgetLookup to list opened buffers.
    pub fn setTextEdits(self: *WidgetLookup, textedits: std.ArrayList(WidgetTextEdit)) !void {
        self.list.reset();

        for (textedits.items) |textedit| {
            try self.list.entries.append(WidgetListEntry{
                .label = try U8Slice.initFromSlice(self.allocator, textedit.editor.buffer.fullpath.bytes()),
                .data = try U8Slice.initFromSlice(self.allocator, textedit.editor.buffer.fullpath.bytes()),
                .data_pos = Vec2i{ .a = -1, .b = -1 }, // unused
                .type = .File,
            });
        }

        try self.list.label.appendConst("Opened buffers:");

        try self.list.filter();
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

test "WidgetLookup init/deinit" {
    // track leaks
    var rv = try WidgetLookup.init(std.testing.allocator);
    rv.deinit();
}
