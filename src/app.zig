const std = @import("std");
const c = @import("clib.zig").c;
const expect = std.testing.expect;

const Buffer = @import("buffer.zig").Buffer;
const BufferPosition = @import("buffer.zig").BufferPosition;
const Colors = @import("colors.zig");
const Draw = @import("draw.zig").Draw;
const Font = @import("font.zig").Font;
const LineStatus = @import("widget_text_edit.zig").LineStatus;
const LSP = @import("lsp.zig").LSP;
const LSPError = @import("lsp.zig").LSPError;
const LSPResponse = @import("lsp.zig").LSPResponse;
const RipgrepResults = @import("ripgrep.zig").RipgrepResults;
const Scaler = @import("scaler.zig").Scaler;
const U8Slice = @import("u8slice.zig").U8Slice;
const WidgetAutocomplete = @import("widget_autocomplete.zig").WidgetAutocomplete;
const WidgetCommand = @import("widget_command.zig").WidgetCommand;
const WidgetCommandError = @import("widget_command.zig").WidgetCommandError;
const WidgetLookup = @import("widget_lookup.zig").WidgetLookup;
const WidgetMessageBox = @import("widget_messagebox.zig").WidgetMessageBox;
const WidgetMessageBoxOverlay = @import("widget_messagebox.zig").WidgetMessageBoxOverlay;
const WidgetMessageBoxType = @import("widget_messagebox.zig").WidgetMessageBoxType;
const WidgetSearchResults = @import("widget_search_results.zig").WidgetSearchResults;
const WidgetTextEdit = @import("widget_text_edit.zig").WidgetTextEdit;

const Vec2f = @import("vec.zig").Vec2f;
const Vec2i = @import("vec.zig").Vec2i;
const Vec2u = @import("vec.zig").Vec2u;
const Vec4u = @import("vec.zig").Vec4u;
const Vec2itou = @import("vec.zig").Vec2itou;
const itou = @import("vec.zig").itou;

pub const AppError = error{
    CantOpenFile,
    CantInit,
};

pub const FocusedWidget = enum {
    Autocomplete,
    Command,
    Editor,
    Lookup,
    MessageBox,
    SearchResults,
};

pub const FocusedEditor = enum {
    Left,
    Right,
};

pub const FontMode = enum {
    LowDPI,
    LowDPIBigFont,
    HiDPI,
};

pub const Direction = enum {
    Up,
    Down,
    Left,
    Right,
};

pub const StoreBufferPositionBehavior = enum {
    /// Previous is used to store the current position when the user is jumping somewhere else
    /// or to jump to a a previous position.
    /// When storing, using Previous delete ones in `next_positions`.
    Previous,
    /// PreviousNoDelete is used to store the current position when the user is jumping somewhere else
    /// or to jump to a a previous position.
    /// When storing, using PreviousNoDelete do NOT delete ones in `next_positions`. Used while going
    /// back and forth.
    PreviousNoDelete,
    /// Next is used to jump to the next position when moving back and forth in positions history.
    Next,
};

/// Main app structure.
/// The app has three fonts mode:
///   * hidpi: using a bigger font but scaled by 0.5, providing the hidpi rendering quality
///   * lowdpi: using a normal font with no scale
///   * lowdpibigfont: using a normal font with no scale, but slightly bigger font than lowdpi
///                    for high resolutions (for the text to not look small).
pub const App = struct {
    allocator: std.mem.Allocator,
    widget_autocomplete: WidgetAutocomplete,
    widget_command: WidgetCommand,
    widget_lookup: WidgetLookup,
    widget_messagebox: WidgetMessageBox,
    widget_search_results: WidgetSearchResults,
    textedits: std.ArrayList(WidgetTextEdit),
    sdl_window: *c.SDL_Window,
    sdl_renderer: *c.SDL_Renderer,

    /// widget_text_edit_pos is the position of the main WidgetTextEdit in the
    /// window. Independant of the scale (i.e. position of the widget in window_scaled_size).
    widget_text_edit_pos: Vec2u,

    /// window_pixel_size is the amount of pixel used to draw the window.
    /// E.g. in a normal resolution, a window of size 800x800 has window_pixel_size
    /// equals to 800x800, whereas on a retina/hidpi screen (let's say with a scale of 1.5x)
    /// the window_pixel_size will be equal to 1600x1600.
    window_pixel_size: Vec2u,
    /// window_scaled_size is the window size.
    /// E.g. in normal resolution, a window of size 800x800 has window_scaled_size
    /// of value 800x800. In a retina/hidpi screen, the window_scaled_size is also
    /// equals to 800x800.
    window_scaled_size: Vec2u,
    /// window_scaling contains the scale between the actual GL rendered
    /// surface and the window size.
    window_scaling: f32,

    // lsp
    lsp: ?*LSP,

    // TODO(remy): comment
    // TODO(remy): tests
    font_lowdpi: Font,
    font_lowdpibigfont: Font,
    font_hidpi: Font,
    font_custom: ?Font,
    current_font: Font,
    font_mode: FontMode,

    /// mainloop is running flag.
    is_running: bool,

    /// working_dir stores the current path to use when opening new files, etc.
    working_dir: U8Slice,

    /// previous_positions is used to be able to get back to a previous positions
    /// when jumping around in source code. See `previous_positions`.
    previous_positions: std.ArrayList(BufferPosition),

    /// next_positions is used to get back to a more recent positions (after having
    /// moved to a previous one with `previous_positions`.
    next_positions: std.ArrayList(BufferPosition),

    /// current_widget_text_edit is the currently selected widget text in the
    /// opened WidgetTextEdits/editors/buffers.
    current_widget_text_edit: usize,

    /// curent_widget_text_edit_alt is the selected textedit in the second
    /// editor.
    current_widget_text_edit_alt: usize,

    /// has_split_view is true if the split view is enabled.
    has_split_view: bool,

    /// focused_editor is the currently focused editor.
    /// If the split view is closed, it will always be .Left.
    focused_editor: FocusedEditor,

    /// focused_widget is the widget which currently has the focus and receives
    /// the events from the keyboard and mouse.
    focused_widget: FocusedWidget,

    // Constructors
    // ------------

    pub fn init(allocator: std.mem.Allocator) !App {
        // SDL init

        if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
            std.log.err("sdl: can't c.SDL_Init(c.SDL_INIT_VIDEO)", .{});
        }

        if (c.TTF_Init() < 0) {
            std.log.err("sdl: can't c.TTF_Init()", .{});
        }

        // create the SDL Window

        const window_size = Vec2u{ .a = 800, .b = 800 };
        const sdl_window = c.SDL_CreateWindow(
            "meh",
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            @as(c_int, @intCast(window_size.a)),
            @as(c_int, @intCast(window_size.b)),
            c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI,
        );

        if (sdl_window == null) {
            std.log.err("App.init: can't create SDL window.", .{});
            return AppError.CantInit;
        }

        // immediately give it the focus

        c.SDL_RaiseWindow(sdl_window);

        // create the renderer

        const sdl_renderer: ?*c.SDL_Renderer = c.SDL_CreateRenderer(sdl_window, -1, c.SDL_RENDERER_ACCELERATED);
        if (sdl_renderer == null) {
            std.log.err("App.init: can't create an SDL Renderer.", .{});
            return AppError.CantInit;
        }

        var info: c.SDL_RendererInfo = undefined;
        _ = c.SDL_GetRendererInfo(sdl_renderer, &info);
        std.log.debug("using SDL renderer: {s}", .{info.name});

        _ = c.SDL_SetRenderDrawBlendMode(sdl_renderer, c.SDL_BLENDMODE_BLEND);

        // load the fonts

        const font_lowdpi = try Font.init(allocator, sdl_renderer.?, 18);
        const font_lowdpibigfont = try Font.init(allocator, sdl_renderer.?, 22);
        const font_hidpi = try Font.init(allocator, sdl_renderer.?, 32);

        // working directory

        var working_dir = U8Slice.initEmpty(allocator);
        const fullpath = try std.fs.realpathAlloc(allocator, ".");
        defer allocator.free(fullpath);
        try working_dir.appendConst(fullpath);

        // return the created app
        return App{
            .allocator = allocator,
            .widget_text_edit_pos = Vec2u{ .a = 0, .b = 8 * 4 },
            .textedits = std.ArrayList(WidgetTextEdit).init(allocator),
            .widget_autocomplete = try WidgetAutocomplete.init(allocator),
            .widget_command = try WidgetCommand.init(allocator),
            .widget_lookup = try WidgetLookup.init(allocator),
            .widget_messagebox = WidgetMessageBox.init(allocator),
            .widget_search_results = try WidgetSearchResults.init(allocator),
            .current_widget_text_edit = 0,
            .current_widget_text_edit_alt = 0,
            .has_split_view = false,
            .sdl_renderer = sdl_renderer.?,
            .is_running = true,
            .previous_positions = std.ArrayList(BufferPosition).init(allocator),
            .next_positions = std.ArrayList(BufferPosition).init(allocator),
            .lsp = null,
            .sdl_window = sdl_window.?,
            .font_custom = undefined,
            .font_lowdpi = font_lowdpi,
            .font_lowdpibigfont = font_lowdpibigfont,
            .font_hidpi = font_hidpi,
            .current_font = font_lowdpi,
            .font_mode = FontMode.LowDPI,
            .focused_editor = FocusedEditor.Left,
            .focused_widget = FocusedWidget.Editor,
            .window_pixel_size = window_size,
            .window_scaled_size = window_size,
            .window_scaling = 1.0,
            .working_dir = working_dir,
        };
    }

    pub fn deinit(self: *App) void {
        for (self.textedits.items) |*textedit| {
            textedit.deinit();
        }
        self.textedits.deinit();

        for (self.previous_positions.items) |pos| {
            pos.deinit();
        }
        self.previous_positions.deinit();

        for (self.next_positions.items) |pos| {
            pos.deinit();
        }
        self.next_positions.deinit();

        self.widget_autocomplete.deinit();
        self.widget_command.deinit();
        self.widget_lookup.deinit();
        self.widget_messagebox.deinit();
        self.widget_search_results.deinit();
        if (self.font_custom) |*custom| {
            custom.deinit();
        }
        self.font_lowdpi.deinit();
        self.font_lowdpibigfont.deinit();
        self.font_hidpi.deinit();

        if (self.lsp) |lsp| {
            lsp.deinit();
        }

        self.working_dir.deinit();

        c.SDL_DestroyRenderer(self.sdl_renderer);
        self.sdl_renderer = undefined;

        c.SDL_DestroyWindow(self.sdl_window);
        self.sdl_window = undefined;

        c.SDL_Quit();

        std.log.debug("bye!", .{});
    }

    // Methods
    // TODO(remy): re-order the methods
    // -------

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn openFile(self: *App, filepath: []const u8) !void {
        // make sure that the provided filepath is absolute
        const path = std.fs.realpathAlloc(self.allocator, filepath) catch |err| {
            std.log.err("App.openFile: can't open {s}: {}", .{ filepath, err });
            return AppError.CantOpenFile;
        };
        defer self.allocator.free(path);

        // first, loop through all buffers to see if it's already opened or not
        var idx: usize = 0;
        for (self.textedits.items) |textedit| {
            // already opened, just switch to it
            if (std.mem.eql(u8, textedit.editor.buffer.fullpath.bytes(), path)) {
                self.setCurrentFocusedWidgetTextEditIndex(idx);
                self.refreshWindowTitle() catch {};
                return;
            }
            idx += 1;
        }

        // open the buffer, create an editor
        var buffer = try Buffer.initFromFile(self.allocator, path);
        var text_edit = try WidgetTextEdit.initWithBuffer(self.allocator, buffer);

        // starts an LSP client if that makes sense.
        if (self.lsp == null) {
            self.startLSPClient(path) catch |err| {
                std.log.err("App.openFile: can't start an LSP client: {}", .{err});
            };
        }

        if (self.lsp) |lsp| {
            lsp.openFile(&buffer) catch |err| {
                std.log.err("App.openFile: can't send openFile to the LSP server: {}", .{err});
            };

            text_edit.editor.lsp = lsp;
        }

        try self.textedits.append(text_edit);

        // switch to this buffer
        self.setCurrentFocusedWidgetTextEditIndex(self.textedits.items.len - 1);
        // immediately trigger its rendering in order to have the WidgetTextEdit
        // compute its viewport.
        self.render();

        self.refreshWindowTitle() catch {};
    }

    /// close closes the current opened editor/buffer.
    /// If it's the last one opened, closes the app.
    // TODO(remy): messagebox to confirm quit
    // TODO(remy): instead of randomly selecting the previous one, store an order
    pub fn closeCurrentFile(self: *App) void {
        if (self.textedits.items.len == 1) {
            self.quit();
            return;
        }

        var text_edit = self.current_widget_text_edit;
        if (self.has_split_view and self.focused_editor == .Right) {
            text_edit = self.current_widget_text_edit_alt;
        }

        // if both the split and the regular view are showing the same file,
        // we will have to update both.
        // -------------
        var change_both: bool = false;
        if (self.current_widget_text_edit_alt == self.current_widget_text_edit) {
            change_both = true;
        }

        // free resources
        // -------------

        var widget = self.textedits.orderedRemove(text_edit);
        widget.deinit();

        // if split view, we may have to update the other index
        // -------------

        if (self.has_split_view and self.focused_editor == .Left) {
            if (self.current_widget_text_edit_alt > text_edit) {
                self.current_widget_text_edit_alt -= 1;
            }
        } else if (self.has_split_view and self.focused_editor == .Right) {
            if (self.current_widget_text_edit > text_edit) {
                self.current_widget_text_edit -= 1;
            }
        }

        // decrease the text edit index we're looking at
        // TODO(remy): this is where we would need some history instead
        // -------------

        if (text_edit == 0) {
            text_edit = self.textedits.items.len - 1;
        } else {
            text_edit -= 1;
        }

        // update what the widget indices
        // -------------

        if (change_both) {
            self.current_widget_text_edit = text_edit;
            self.current_widget_text_edit_alt = text_edit;
        } else {
            if (self.has_split_view and self.focused_editor == .Right) {
                self.current_widget_text_edit_alt = text_edit;
            } else {
                self.current_widget_text_edit = text_edit;
            }
        }

        self.refreshWindowTitle() catch {};
    }

    /// startLSPClient identifies and starts an LSP server if none has been spawned for the
    /// given file.
    pub fn startLSPClient(self: *App, fullpath: []const u8) !void {
        if (self.lsp != null) {
            return;
        }

        std.log.debug("App.startLSPClient: starting an LSP client for {s}", .{fullpath});

        var extension = std.fs.path.extension(fullpath);
        const lsp_server = LSP.serverFromExtension(extension) catch |err| {
            if (err != LSPError.UnknownExtension) {
                std.log.err("App.startLSPClient: can't start an LSP server: {}", .{err});
            }
            return;
        };

        self.lsp = try LSP.init(self.allocator, lsp_server, extension[1..], self.working_dir.bytes());
        if (self.lsp) |lsp| {
            try lsp.initialize();
            try lsp.initialized();
        }
    }

    /// currentWidgetTextEdit returns the currently focused WidgetTextEdit.
    // FIXME(remy): this method isn't testing anything and will crash the
    // app if no file is opened.
    pub fn currentWidgetTextEdit(self: App) *WidgetTextEdit {
        if (self.has_split_view and self.focused_editor == .Right) {
            return &self.textedits.items[self.current_widget_text_edit_alt];
        }
        return &self.textedits.items[self.current_widget_text_edit];
    }

    /// refreshWindowTitle refreshes the WM window title using the currently
    /// focused WidgetText editor information.
    fn refreshWindowTitle(self: App) !void {
        const wte = self.currentWidgetTextEdit();
        var title = try U8Slice.initFromSlice(self.allocator, "meh - ");
        defer title.deinit();

        if (std.fs.path.dirname(wte.editor.buffer.fullpath.data.items)) |dir| {
            try title.appendConst(std.fs.path.basename(dir)); // we only want the dir right before
            try title.appendConst("/");
        }

        const file = std.fs.path.basename(wte.editor.buffer.fullpath.data.items);
        try title.appendConst(file);

        try title.data.append(0); // turn it into a C string
        c.SDL_SetWindowTitle(self.sdl_window, @as([*:0]const u8, @ptrCast(title.data.items)));
    }

    /// setCurrentFocusedWidgetTextEditIndex is used to set the active WidgetTextEdit index (the
    /// right of the left one).
    fn setCurrentFocusedWidgetTextEditIndex(self: *App, index: usize) void {
        if (self.has_split_view and self.focused_editor == .Right) {
            self.current_widget_text_edit_alt = index;
        } else {
            self.current_widget_text_edit = index;
        }
    }

    /// toggleSplit closes and opens the split view.
    pub fn toggleSplit(self: *App) void {
        self.has_split_view = !self.has_split_view;

        if (self.has_split_view) {
            self.focused_editor = .Right;
        }

        if (!self.has_split_view) {
            self.focused_editor = .Left;
        }

        self.refreshWindowTitle() catch {};
    }

    /// storeBufferPosition stores the current position of the cursor in the active buffer.
    pub fn storeBufferPosition(self: *App, direction: StoreBufferPositionBehavior) void {
        if (self.textedits.items.len == 0) {
            return;
        }

        const textedit = self.currentWidgetTextEdit();
        const buffer_pos = BufferPosition{
            .fullpath = textedit.editor.buffer.fullpath.copy(self.allocator) catch |err| {
                std.log.err("App.storeBufferPosition: can't copy buffer fullpath: {}", .{err});
                return;
            },
            .cursor_position = textedit.cursor.pos,
        };

        switch (direction) {
            .Previous => {
                self.previous_positions.append(buffer_pos) catch |err| {
                    std.log.err("App.storeBufferPosition: can't store previous buffer position: {}", .{err});
                };

                // since we're adding a new position, all the ones in next_positions have to disappear
                while (self.next_positions.items.len > 0) {
                    self.next_positions.pop().deinit();
                }
            },
            .PreviousNoDelete => {
                self.previous_positions.append(buffer_pos) catch |err| {
                    std.log.err("App.storeBufferPosition: can't store previous buffer position: {}", .{err});
                };
            },
            .Next => {
                self.next_positions.append(buffer_pos) catch |err| {
                    std.log.err("App.storeBufferPosition: can't store next buffer position: {}", .{err});
                };
            },
        }

        // TODO(remy): don't grow indefinitely
    }

    /// jumpToPrevious jumps back to the previous position in `previous_positions`.
    /// See jumpToNext and jumpToBufferPosition.
    pub fn jumpToPrevious(self: *App) !void {
        if (self.previous_positions.items.len == 0) {
            return;
        }

        const buff_pos = self.previous_positions.pop();
        defer buff_pos.deinit();

        self.storeBufferPosition(.Next);

        return try self.jumpToBufferPosition(buff_pos);
    }

    /// jumpToNext jumps back to the next position in `next_positions`.
    /// See jumpToPrevious and jumpToBufferPosition.
    pub fn jumpToNext(self: *App) !void {
        if (self.next_positions.items.len == 0) {
            return;
        }

        const buff_pos = self.next_positions.pop();
        defer buff_pos.deinit();

        self.storeBufferPosition(.PreviousNoDelete);

        return try self.jumpToBufferPosition(buff_pos);
    }

    /// jumpToBufferPosition jumps to the given buffer position, trying to open the file
    /// if necessary.
    pub fn jumpToBufferPosition(self: *App, buff_pos: BufferPosition) !void {
        try self.openFile(buff_pos.fullpath.bytes());
        self.currentWidgetTextEdit().goTo(buff_pos.cursor_position, .Center);
    }

    /// peekLine reads a file until the given line and returns that line in a new U8Slice.
    /// Could used either a buffered already loaded or the file from the filesystem.
    /// Memory of the U8Slice is owned by the caller and should be freed accordingly.
    // TODO(remy): unit test
    pub fn peekLine(self: *App, filepath: []const u8, line: usize) !U8Slice {
        // make sure that the provided fullpath is absolute
        const fullpath = try std.fs.realpathAlloc(self.allocator, filepath);
        defer self.allocator.free(fullpath);

        // check if we have this data in loaded buffers
        // -------------

        for (self.textedits.items) |textedit| {
            if (std.mem.eql(u8, textedit.editor.buffer.fullpath.bytes(), fullpath)) {
                var l = try textedit.editor.buffer.getLine(line);
                return try l.copy(self.allocator);
            }
        }

        // we don't have this data available, peek on the filesystem
        // -------------

        var file = try std.fs.cwd().openFile(fullpath, .{});
        defer file.close();

        const block_size = 4096;
        var slice: [block_size]u8 = undefined;
        var buff = &slice;
        var read: usize = block_size;

        var buf_reader = std.io.bufferedReader(file.reader());
        var rv = U8Slice.initEmpty(self.allocator);
        errdefer rv.deinit();

        var i: usize = 0;
        var current_line: usize = 0;
        var line_offset: usize = 0;

        while (read == block_size) {
            i = 0;
            line_offset = 0;
            read = try buf_reader.reader().read(buff);

            while (i < read) : (i += 1) {
                if (buff[i] == '\n') {
                    if (current_line == line) {
                        // append the data left until the \n with the \n included
                        try rv.appendConst(buff[line_offset .. i + 1]); // allocate the data in an u8slice
                    }
                    // move the cursor in this buffer
                    line_offset = i + 1;
                    current_line += 1;
                }
            }

            // append the rest of the read buffer if part of peeked line.
            if (current_line == line) {
                try rv.appendConst(buff[line_offset..read]);
            }
        }

        return rv;
    }

    /// openRipgrepResults opens the WidgetSearchResults with the given results if there are any.
    pub fn openRipgrepResults(self: *App, results: RipgrepResults) void {
        if (results.stdout.len == 0) {
            self.showMessageBoxError("No results.", .{});
            return;
        }

        self.widget_search_results.setRipgrepResults(results) catch |err| {
            std.log.err("App.openRipgrepResults: {}", .{err});
        };

        self.focused_widget = .SearchResults;
    }

    pub fn increaseFont(self: *App) void {
        const font = Font.init(self.allocator, self.sdl_renderer, self.current_font.font_size + 2) catch |err| {
            std.log.err("App.increaseFont: can't load temporary font: {}", .{err});
            return;
        };

        if (self.font_custom) |*custom| {
            custom.deinit();
        }

        self.font_custom = font;
        self.current_font = font;
    }

    fn render(self: *App) void {
        // grab screen information every render pass
        // -----------------------------------------

        self.refreshWindowPixelSize();
        self.refreshWindowScaledSize();
        self.refreshDPIMode();
        const scaler = Scaler{ .scale = self.window_scaling };
        const one_char_size = self.oneCharSize();

        // render list
        // -----------

        // clean up between passes

        _ = c.SDL_SetRenderDrawColor(self.sdl_renderer, 30, 30, 30, 255);
        _ = c.SDL_RenderClear(self.sdl_renderer);

        // editor window

        if (self.current_widget_text_edit < self.textedits.items.len) {
            var widget_size = Vec2u{ .a = self.window_scaled_size.a, .b = self.window_scaled_size.b - one_char_size.b };
            if (self.has_split_view) {
                widget_size.a /= 2;
            }

            var widget_text_edit = &self.textedits.items[self.current_widget_text_edit];

            Draw.text(self.current_font, scaler, Vec2u{ .a = 2, .b = 2 }, widget_size.a, Colors.white, widget_text_edit.editor.buffer.fullpath.bytes());

            widget_text_edit.render(
                self.sdl_renderer,
                self.current_font,
                scaler,
                self.widget_text_edit_pos,
                widget_size,
                one_char_size,
                self.focused_editor == .Left,
            );

            if (self.has_split_view and self.current_widget_text_edit_alt < self.textedits.items.len) {
                var split_pos = self.widget_text_edit_pos;
                split_pos.a = self.window_scaled_size.a / 2;

                Draw.line(
                    self.sdl_renderer,
                    scaler,
                    Vec2u{ .a = split_pos.a - 1, .b = split_pos.b },
                    Vec2u{ .a = split_pos.a - 1, .b = widget_size.b },
                    Vec4u{ .a = 70, .b = 70, .c = 70, .d = 255 },
                );

                var widget_text_edit_alt = &self.textedits.items[self.current_widget_text_edit_alt];

                Draw.text(self.current_font, scaler, Vec2u{ .a = split_pos.a, .b = 2 }, widget_size.a, Colors.white, widget_text_edit_alt.editor.buffer.fullpath.bytes());

                widget_text_edit_alt.render(
                    self.sdl_renderer,
                    self.current_font,
                    scaler,
                    split_pos,
                    widget_size,
                    one_char_size,
                    self.focused_editor == .Right,
                );
            }
        }

        // widgets

        switch (self.focused_widget) {
            .Autocomplete => {
                const wt = self.currentWidgetTextEdit();
                var cursor_pixel_pos = wt.cursor.posInPixel(wt, wt.one_char_size);
                if (self.has_split_view and self.focused_editor == .Right) {
                    cursor_pixel_pos.a += self.window_scaled_size.a / 2;
                }
                self.widget_autocomplete.render(
                    self.sdl_renderer,
                    self.current_font,
                    scaler,
                    self.window_scaled_size,
                    cursor_pixel_pos,
                    one_char_size,
                );
            },
            .Command => self.widget_command.render(
                self.sdl_renderer,
                self.current_font,
                scaler,
                self.window_scaled_size, // used for the overlay
                Vec2u{ .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.a)) * 0.1)), .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.b)) * 0.1)) },
                Vec2u{ .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.a)) * 0.8)), .b = 50 },
                one_char_size,
            ),
            .MessageBox => self.widget_messagebox.render(
                self.sdl_renderer,
                self.current_font,
                scaler,
                self.window_scaled_size, // used for the overlay
                one_char_size,
            ),
            .Lookup => self.widget_lookup.render(
                self.sdl_renderer,
                self.current_font,
                scaler,
                self.window_scaled_size, // used for the overlay
                Vec2u{ .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.a)) * 0.1)), .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.b)) * 0.1)) },
                Vec2u{ .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.a)) * 0.8)), .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.b)) * 0.8)) },
                one_char_size,
            ),
            .SearchResults => self.widget_search_results.render(
                self.sdl_renderer,
                self.current_font,
                scaler,
                self.window_scaled_size, // used for the overlay
                Vec2u{ .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.a)) * 0.1)), .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.b)) * 0.1)) },
                Vec2u{ .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.a)) * 0.8)), .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.window_scaled_size.b)) * 0.8)) },
                one_char_size,
            ),
            else => {}, // nothing more to render then
        }

        // rendering
        _ = c.SDL_RenderPresent(self.sdl_renderer);
    }

    fn setFontMode(self: *App, font_mode: FontMode) void {
        switch (font_mode) {
            .LowDPI => {
                self.current_font = self.font_lowdpi;
                self.widget_text_edit_pos.b = 16 + 4;
            },
            .LowDPIBigFont => {
                self.current_font = self.font_lowdpibigfont;
                self.widget_text_edit_pos.b = 20 + 4;
            },
            .HiDPI => {
                self.current_font = self.font_hidpi;
                self.widget_text_edit_pos.b = 16 + 4;
            },
        }
        self.font_mode = font_mode;
    }

    /// refreshWindowPixelSize refreshes the window pixel size.
    fn refreshWindowPixelSize(self: *App) void {
        var gl_w: c_int = 0;
        var gl_h: c_int = 0;
        c.SDL_GL_GetDrawableSize(self.sdl_window, &gl_w, &gl_h);
        self.window_pixel_size.a = @as(usize, @intCast(gl_w));
        self.window_pixel_size.b = @as(usize, @intCast(gl_h));
    }

    /// refreshWindowScaledSize refreshes the window size (scaled).
    fn refreshWindowScaledSize(self: *App) void {
        var w: c_int = 0;
        var h: c_int = 0;
        c.SDL_GetWindowSize(self.sdl_window, &w, &h);
        self.window_scaled_size.a = @as(usize, @intCast(w));
        self.window_scaled_size.b = @as(usize, @intCast(h));
    }

    /// refreshDPIMode refreshes the DPI mode using the stored window pixel size
    /// and stored window scaled size.
    fn refreshDPIMode(self: *App) void {
        const display_index: c_int = c.SDL_GetWindowDisplayIndex(self.sdl_window);
        var desktop_resolution: c.SDL_DisplayMode = undefined;
        _ = c.SDL_GetDesktopDisplayMode(display_index, &desktop_resolution); // get the resolution

        if ((self.window_pixel_size.a > self.window_scaled_size.a and self.window_pixel_size.b > self.window_scaled_size.b and self.font_mode != FontMode.HiDPI)) {
            // hidpi
            self.window_scaling = @as(f32, @floatFromInt(self.window_pixel_size.a)) / @as(f32, @floatFromInt(self.window_scaled_size.a));
            self.setFontMode(FontMode.HiDPI);
        } else if (self.window_scaled_size.a == self.window_pixel_size.a and self.window_scaled_size.b == self.window_pixel_size.b) {
            // lowdpi
            self.window_scaling = 1.0;
            if (desktop_resolution.h < 2000 and self.font_mode != FontMode.LowDPI) {
                self.setFontMode(FontMode.LowDPI);
            } else if (desktop_resolution.h > 2000 and self.font_mode != FontMode.LowDPIBigFont) {
                self.setFontMode(FontMode.LowDPIBigFont);
            }
        }
        // the viewport may have to be resized
        self.onWindowResized();
    }

    /// oneCharSize returns the bounding box of one text char.
    fn oneCharSize(self: App) Vec2u {
        return Vec2u{
            .a = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.current_font.font_size / 2)) / self.window_scaling)),
            .b = @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.current_font.font_size)) / self.window_scaling)),
        };
    }

    // TODO(remy): comment
    // TODO(remy): unit test
    pub fn quit(self: *App) void {
        // TODO(remy): messagebox to save
        self.is_running = false;
    }

    /// showMessageBoxError displays a small error message closable with Escape or Return.
    pub fn showMessageBoxError(self: *App, comptime label: []const u8, args: anytype) void {
        const message = std.fmt.allocPrint(self.allocator, label, args) catch |err| {
            std.log.err("App.showMessageBoxError: can't show messagebox error: {}", .{err});
            return;
        };
        defer self.allocator.free(message);

        self.widget_messagebox.set(label, .Error, .WithOverlay) catch |err| {
            std.log.err("App.showMessageBoxError: can't show messagebox error: {}", .{err});
            return;
        };

        self.focused_widget = .MessageBox;
        self.render();
    }

    // TODO(remy): comment
    // labels are copied in the messagebox, the caller is responsible of original labels memory.
    pub fn showMessageBoxMultiple(self: *App, lines: std.ArrayList(U8Slice), box_type: WidgetMessageBoxType, with_overlay: WidgetMessageBoxOverlay) void {
        self.widget_messagebox.setMultiple(lines, box_type, with_overlay) catch |err| {
            std.log.err("App.showMessageBoxMultiple: can't open messagebox: {}", .{err});
            return;
        };

        self.focused_widget = .MessageBox;
        self.render();
    }

    // TODO(remy): comment
    // message content is copied in the messagebox, the caller is responsible of
    // the original message memory.
    pub fn showMessageBox(self: *App, message: U8Slice, box_type: WidgetMessageBoxType, with_overlay: WidgetMessageBoxOverlay) void {
        if (self.focused_widget == .MessageBox) {
            self.widget_messagebox.append(message.bytes()) catch |err| {
                std.log.err("App.showMessageBox: can't append line to messagebox: {}", .{err});
                return;
            };
        } else {
            self.widget_messagebox.set(message.bytes(), box_type, with_overlay) catch |err| {
                std.log.err("App.showMessageBox: can't open messagebox: {}", .{err});
                return;
            };
        }

        self.focused_widget = .MessageBox;
        self.render();
    }

    /// onWindowResized is called when the windows has just been resized.
    fn onWindowResized(self: *App) void {
        self.refreshWindowPixelSize();
        self.refreshWindowScaledSize();
    }

    /// mainloop of the application.
    pub fn mainloop(self: *App) !void {
        var event: c.SDL_Event = undefined;
        self.is_running = true;
        var to_render = true;
        c.SDL_StartTextInput();

        const frame_per_second = 60;
        const max_ms_skip = 1000 / frame_per_second;
        var start = std.time.milliTimestamp();
        var focused_widget = self.focused_widget;

        // immediately trigger a first render pass for responsiveness when the
        // window appears.
        self.onWindowResized();
        self.render();

        // mainloop
        while (self.is_running) {
            start = std.time.milliTimestamp();

            // events handling
            // ---------------

            while (c.SDL_PollEvent(&event) > 0) {
                if (event.type == c.SDL_QUIT) {
                    self.quit();
                    break;
                }

                // events to handle independently of the currently focused widget
                switch (event.type) {
                    c.SDL_WINDOWEVENT => {
                        if (event.window.event == c.SDL_WINDOWEVENT_SIZE_CHANGED) {
                            self.onWindowResized();
                        }
                    },
                    else => {},
                }

                // events to handle differently per focused widget
                focused_widget = self.focused_widget;
                switch (self.focused_widget) {
                    .Autocomplete => {
                        self.autocompleteEvents(event);
                        to_render = true;
                    },
                    .Command => {
                        self.commandEvents(event);
                        to_render = true;
                    },
                    .Editor => {
                        self.editorEvents(event);
                        to_render = true;
                    },
                    .Lookup => {
                        self.lookupEvents(event);
                        to_render = true;
                    },
                    .SearchResults => {
                        self.searchResultsEvents(event);
                        to_render = true;
                    },
                    .MessageBox => {
                        self.messageBoxEvents(event);
                    },
                }

                // the focus widget changed, trigger an immedate repaint
                //                if (self.focused_widget != focused_widget) {
                //                    self.render();
                //                    focused_widget = self.focused_widget;
                //                }
            }

            // LSP messages handling
            // ---------------------

            if (self.lsp) |lsp| {
                while (!lsp.context.response_queue.isEmpty()) {
                    var node = lsp.context.response_queue.get().?;
                    if (self.interpretLSPMessage(node.data)) {
                        to_render = true;
                    }
                    node.data.deinit();
                    lsp.context.allocator.destroy(node);
                }
            }

            // rendering
            // ---------

            if (to_render) {
                self.render();
                to_render = false;
            }

            var max_sleep_ms = max_ms_skip - (std.time.milliTimestamp() - start);
            if (max_sleep_ms < 0) {
                max_sleep_ms = 0;
            }
            std.time.sleep(itou(max_sleep_ms * std.time.ns_per_ms));
        }

        c.SDL_StopTextInput();
    }

    // LSP
    // -----------------------

    fn interpretLSPMessage(self: *App, response: LSPResponse) bool {
        switch (response.message_type) {
            .Completion => {
                if (response.completions) |completions| {
                    self.widget_autocomplete.setCompletionItems(completions) catch |err| {
                        self.showMessageBoxError("LSP: can't display completions items: {}", .{err});
                    };
                } else {
                    self.widget_autocomplete.setNoResults();
                }
                return true;
            },
            .Definition => {
                if (response.definitions) |definitions| {
                    // TODO(remy): support multiple definitions
                    if (definitions.items.len > 1) {
                        std.log.warn("App.interpretLSPMessage: multiple definitions ({d}) have been returned", .{definitions.items.len});
                    }

                    self.storeBufferPosition(.Previous);

                    var definition = definitions.items[0];
                    if (self.openFile(definition.filepath.bytes())) {
                        self.currentWidgetTextEdit().goTo(definition.start, .Center);
                        self.currentWidgetTextEdit().setInputMode(.Command);
                    } else |err| {
                        self.showMessageBoxError("LSP: error while jumping to definition: {}", .{err});
                        std.log.debug("App.mainloop: can't jump to LSP definition: {}", .{err});
                    }
                } else {
                    self.showMessageBoxError("LSP: can't find definition.", .{});
                }
                return true;
            },
            .Hover => {
                if (response.hover == null or response.hover.?.items.len == 0) {
                    self.showMessageBoxError("LSP: empty hover.", .{});
                }

                if (response.hover) |hover| {
                    self.showMessageBoxMultiple(hover, .LSPHover, .WithoutOverlay);
                }

                return true;
            },
            .LogMessage => {
                if (response.log_message == null or response.log_message.?.isEmpty()) {
                    return true;
                }

                if (response.log_message) |log_message| {
                    self.showMessageBox(log_message, .LSPMessage, .WithOverlay);
                }
            },
            .References => {
                if (response.references == null or response.references.?.items.len == 0) {
                    self.showMessageBoxError("LSP: no references found.", .{});
                }
                if (response.references) |references| {
                    self.widget_search_results.setLspReferences(self, references) catch |err| {
                        self.showMessageBoxError("LSP: can't display references: {}", .{err});
                    };
                    self.focused_widget = .SearchResults;
                }
                return true;
            },
            .ClearDiagnostics => { // we still need one entry to get the filepath
                if (response.diagnostics == null or response.diagnostics.?.items.len == 0) {
                    return true;
                }

                for (response.diagnostics.?.items) |diagnostic| {
                    // TODO(remy): implements App.getWidgetTextEditByFilepath()
                    for (self.textedits.items) |*textedit| {
                        if (std.mem.eql(u8, textedit.editor.buffer.fullpath.bytes(), diagnostic.filepath.bytes())) {
                            textedit.clearDiagnostics();
                        }
                    }
                }

                return true;
            },
            .Diagnostic => {
                if (response.diagnostics == null or response.diagnostics.?.items.len == 0) {
                    return true;
                }
                var first: bool = true;
                for (response.diagnostics.?.items) |diagnostic| {
                    // TODO(remy): implements App.getWidgetTextEditByFilepath()
                    for (self.textedits.items) |*textedit| {
                        if (std.mem.eql(u8, textedit.editor.buffer.fullpath.bytes(), diagnostic.filepath.bytes())) {
                            // when starting to process diagnostics, first thing we want to do
                            // is to clear the map.
                            if (first) {
                                textedit.clearDiagnostics();
                                first = false;
                            }
                            const message = diagnostic.message.copy(self.allocator) catch |err| {
                                std.log.err("App.interpretLSPMessage: can't copy the message: {}", .{err});
                                continue;
                            };

                            // there is an existing entry at this line, remove it first.
                            // TODO(remy): we could have multiple entries
                            if (textedit.lines_status.get(diagnostic.range.b)) |line_status| {
                                if (textedit.lines_status.remove(diagnostic.range.b)) {
                                    line_status.deinit();
                                }
                            }

                            textedit.lines_status.put(diagnostic.range.b, LineStatus{
                                .message = message,
                                .type = .Diagnostic,
                            }) catch |err| {
                                std.log.err("App.interpretLSPMessage: can't add a diagnostic: {}", .{err});
                            };
                        }
                    }
                }
                return true;
            },
            .Initialize => {}, // nothing to do
            else => std.log.debug("App.mainloop: unsupported LSP message received: {}", .{response}),
        }
        return false;
    }

    // Widgets events handling
    // -----------------------

    fn autocompleteEvents(self: *App, event: c.SDL_Event) void {
        const input_state = c.SDL_GetKeyboardState(null);
        const ctrl: bool = input_state[c.SDL_SCANCODE_LCTRL] == 1 or input_state[c.SDL_SCANCODE_RCTRL] == 1;
        switch (event.type) {
            c.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    c.SDLK_RETURN => {
                        if (self.widget_autocomplete.select()) |autocomplete_entry| {
                            if (autocomplete_entry) |entry| {
                                const wt = self.currentWidgetTextEdit();
                                // remove the filter if any has been entered
                                if (self.widget_autocomplete.list.input.text()) |text| {
                                    // first remove the extra text inserted while filtering
                                    var remove_start = Vec2u{ .a = wt.cursor.pos.a - text.size(), .b = wt.cursor.pos.b };
                                    var remove_end = wt.cursor.pos;
                                    if (wt.editor.deleteChunk(
                                        remove_start,
                                        remove_end,
                                        .Input,
                                    )) |new_pos| {
                                        wt.setCursorPos(new_pos, .Scroll);
                                    } else |_| {}

                                    // then, if any, remove the range provided by the lsp completion entry
                                    if (entry.data_range) |range| {
                                        remove_start = Vec2u{ .a = range.a, .b = range.b };
                                        remove_end = Vec2u{ .a = range.c, .b = range.d };

                                        if (wt.editor.deleteChunk(
                                            remove_start,
                                            remove_end,
                                            .Input,
                                        )) |new_pos| {
                                            wt.setCursorPos(new_pos, .Scroll);
                                        } else |_| {}
                                    }
                                } else |_| {}
                                // insert the completion
                                wt.editor.insertUtf8Text(wt.cursor.pos, entry.data.bytes(), .Input) catch |err| {
                                    self.showMessageBoxError("LSP: can't insert value (insert completion): {}", .{err});
                                };
                                wt.setCursorPos(Vec2u{ .a = wt.cursor.pos.a + entry.data.size(), .b = wt.cursor.pos.b }, .Scroll);
                            }
                        } else |err| {
                            self.showMessageBoxError("LSP: can't insert value: {}", .{err});
                        }
                        self.focused_widget = FocusedWidget.Editor;
                        self.widget_autocomplete.reset();
                    },
                    c.SDLK_ESCAPE => {
                        self.focused_widget = FocusedWidget.Editor;
                        self.widget_autocomplete.reset();
                    },
                    c.SDLK_BACKSPACE => {
                        self.currentWidgetTextEdit().onBackspace();
                        self.widget_autocomplete.list.onBackspace();
                    },
                    c.SDLK_n, c.SDLK_DOWN => {
                        if (ctrl or event.key.keysym.sym == c.SDLK_DOWN) {
                            self.widget_autocomplete.list.next();
                        }
                    },
                    c.SDLK_p, c.SDLK_UP => {
                        if (ctrl or event.key.keysym.sym == c.SDLK_UP) {
                            self.widget_autocomplete.list.previous();
                        }
                    },
                    else => {},
                }
            },
            c.SDL_TEXTINPUT => {
                const read_text = readTextFromSDLInput(&event.text.text);
                _ = self.currentWidgetTextEdit().onTextInput(read_text);
                _ = self.widget_autocomplete.list.onTextInput(read_text);
                self.widget_autocomplete.filter_size += 1;
            },
            else => {},
        }
    }

    fn commandEvents(self: *App, event: c.SDL_Event) void {
        switch (event.type) {
            c.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    c.SDLK_RETURN => {
                        self.focused_widget = FocusedWidget.Editor;
                        self.widget_command.interpret(self) catch |err| {
                            if (err == WidgetCommandError.UnknownCommand) {
                                self.showMessageBoxError("Unknown command.", .{});
                                return;
                            }
                            std.log.err("App.commandEvents: can't interpret: {}", .{err});
                            return;
                        };
                        self.widget_command.reset();
                    },
                    c.SDLK_ESCAPE => {
                        self.focused_widget = FocusedWidget.Editor;
                        self.widget_command.reset();
                    },
                    c.SDLK_BACKSPACE => {
                        self.widget_command.onBackspace();
                    },
                    c.SDLK_UP => self.widget_command.onArrowKey(.Up),
                    c.SDLK_DOWN => self.widget_command.onArrowKey(.Down),
                    c.SDLK_LEFT => self.widget_command.onArrowKey(.Left),
                    c.SDLK_RIGHT => self.widget_command.onArrowKey(.Right),
                    else => {},
                }
            },
            c.SDL_TEXTINPUT => {
                _ = self.widget_command.onTextInput(readTextFromSDLInput(&event.text.text));
            },
            else => {},
        }
    }

    fn messageBoxEvents(self: *App, event: c.SDL_Event) void {
        switch (event.type) {
            c.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    c.SDLK_RETURN => {
                        self.focused_widget = .Editor;
                    },
                    c.SDLK_ESCAPE => {
                        self.focused_widget = .Editor;
                    },
                    c.SDLK_j, c.SDLK_DOWN => {
                        self.widget_messagebox.y_offset += 1;
                        self.render();
                    },
                    c.SDLK_k, c.SDLK_UP => {
                        if (self.widget_messagebox.y_offset > 0) {
                            self.widget_messagebox.y_offset -= 1;
                        }
                        self.render();
                    },
                    c.SDLK_l, c.SDLK_RIGHT => {
                        self.widget_messagebox.x_offset += 1;
                        self.render();
                    },
                    c.SDLK_h, c.SDLK_LEFT => {
                        if (self.widget_messagebox.x_offset > 0) {
                            self.widget_messagebox.x_offset -= 1;
                        }
                        self.render();
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    fn searchResultsEvents(self: *App, event: c.SDL_Event) void {
        const input_state = c.SDL_GetKeyboardState(null);
        const ctrl: bool = input_state[c.SDL_SCANCODE_LCTRL] == 1 or input_state[c.SDL_SCANCODE_RCTRL] == 1;
        switch (event.type) {
            c.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    c.SDLK_RETURN => {
                        if (self.widget_search_results.select()) |selected| {
                            if (selected) |entry| {
                                self.storeBufferPosition(.Previous);

                                self.openFile(entry.data.bytes()) catch |err| {
                                    std.log.debug("App.lookupEvents: can't open file: {}", .{err});
                                    return;
                                };
                                self.currentWidgetTextEdit().goTo(Vec2itou(entry.data_pos), .Center);
                                // leave the WidgetSearchResults widget
                                self.focused_widget = FocusedWidget.Editor;
                            }
                        } else |err| {
                            std.log.err("App.searchResultsEvents: can't select current entry: {}", .{err});
                        }
                    },
                    c.SDLK_BACKSPACE => {
                        self.widget_search_results.list.onBackspace();
                    },
                    c.SDLK_ESCAPE => {
                        self.focused_widget = FocusedWidget.Editor;
                    },
                    c.SDLK_n, c.SDLK_DOWN => {
                        if (ctrl or event.key.keysym.sym == c.SDLK_DOWN) {
                            self.widget_search_results.list.next();
                        }
                    },
                    c.SDLK_p, c.SDLK_UP => {
                        if (ctrl or event.key.keysym.sym == c.SDLK_UP) {
                            self.widget_search_results.list.previous();
                        }
                    },
                    c.SDLK_u => {
                        if (ctrl) {
                            self.widget_search_results.list.previousPage();
                        }
                    },
                    c.SDLK_d => {
                        if (ctrl) {
                            self.widget_search_results.list.nextPage();
                        }
                    },
                    c.SDLK_LEFT => {
                        self.widget_search_results.list.left();
                    },
                    c.SDLK_RIGHT => {
                        self.widget_search_results.list.right();
                    },
                    else => {},
                }
            },
            c.SDL_TEXTINPUT => {
                _ = self.widget_search_results.list.onTextInput(readTextFromSDLInput(&event.text.text));
            },
            else => {},
        }
    }

    fn lookupEvents(self: *App, event: c.SDL_Event) void {
        const input_state = c.SDL_GetKeyboardState(null);
        const ctrl: bool = input_state[c.SDL_SCANCODE_LCTRL] == 1 or input_state[c.SDL_SCANCODE_RCTRL] == 1;
        //        var shift: bool = input_state[c.SDL_SCANCODE_LSHIFT] == 1 or input_state[c.SDL_SCANCODE_RSHIFT] == 1;
        //        var cmd: bool = input_state[c.SDL_SCANCODE_LGUI] == 1 or input_state[c.SDL_SCANCODE_RGUI] == 1;
        switch (event.type) {
            c.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    c.SDLK_RETURN => {
                        if (self.widget_lookup.select()) |selected| {
                            if (selected) |entry| {
                                self.storeBufferPosition(.Previous);

                                // we'll try to open that file
                                self.openFile(entry.data.bytes()) catch |err| {
                                    std.log.debug("App.lookupEvents: can't open file: {}", .{err});
                                    return;
                                };
                                // leave the widget
                                self.focused_widget = FocusedWidget.Editor;
                            }
                        } else |err| {
                            std.log.err("App.lookupEvents: can't select current entry: {}", .{err});
                        }
                    },
                    c.SDLK_BACKSPACE => {
                        self.widget_lookup.list.onBackspace();
                    },
                    c.SDLK_ESCAPE => {
                        self.widget_lookup.list.reset();
                        self.focused_widget = FocusedWidget.Editor;
                    },
                    c.SDLK_n, c.SDLK_DOWN => {
                        if (ctrl or event.key.keysym.sym == c.SDLK_DOWN) {
                            self.widget_lookup.list.next();
                        }
                    },
                    c.SDLK_p, c.SDLK_UP => {
                        if (ctrl or event.key.keysym.sym == c.SDLK_UP) {
                            self.widget_lookup.list.previous();
                        }
                    },
                    c.SDLK_u => {
                        if (ctrl) {
                            self.widget_lookup.list.previousPage();
                        }
                    },
                    c.SDLK_d => {
                        if (ctrl) {
                            self.widget_lookup.list.nextPage();
                        }
                    },
                    c.SDLK_LEFT => {
                        self.widget_lookup.list.left();
                    },
                    c.SDLK_RIGHT => {
                        self.widget_lookup.list.right();
                    },
                    else => {},
                }
            },
            c.SDL_TEXTINPUT => {
                _ = self.widget_lookup.list.onTextInput(readTextFromSDLInput(&event.text.text));
            },
            else => {},
        }
    }

    fn editorEvents(self: *App, event: c.SDL_Event) void {
        const input_state = c.SDL_GetKeyboardState(null);
        const ctrl: bool = input_state[c.SDL_SCANCODE_LCTRL] == 1 or input_state[c.SDL_SCANCODE_RCTRL] == 1;
        const shift: bool = input_state[c.SDL_SCANCODE_LSHIFT] == 1 or input_state[c.SDL_SCANCODE_RSHIFT] == 1;
        const cmd: bool = input_state[c.SDL_SCANCODE_LGUI] == 1 or input_state[c.SDL_SCANCODE_RGUI] == 1;
        switch (event.type) {
            c.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    c.SDLK_RETURN => {
                        self.currentWidgetTextEdit().onReturn();
                    },
                    c.SDLK_ESCAPE => _ = self.currentWidgetTextEdit().onEscape(),
                    c.SDLK_COLON => {
                        if (self.currentWidgetTextEdit().input_mode == .Command) {
                            self.focused_widget = FocusedWidget.Command;
                        }
                    },
                    c.SDLK_BACKSPACE => {
                        self.currentWidgetTextEdit().onBackspace();
                    },
                    c.SDLK_EQUALS => {
                        if ((ctrl or cmd) and shift) {
                            self.increaseFont();
                        }
                    },
                    c.SDLK_TAB => {
                        self.currentWidgetTextEdit().onTab(shift);
                    },
                    c.SDLK_UP => self.currentWidgetTextEdit().onArrowKey(.Up),
                    c.SDLK_DOWN => self.currentWidgetTextEdit().onArrowKey(.Down),
                    c.SDLK_LEFT => self.currentWidgetTextEdit().onArrowKey(.Left),
                    c.SDLK_RIGHT => self.currentWidgetTextEdit().onArrowKey(.Right),
                    else => {
                        if (ctrl) {
                            // TODO(remy): move to a specific fn
                            switch (event.key.keysym.sym) {
                                c.SDLK_j => {
                                    if (!self.has_split_view) {
                                        return;
                                    }
                                    if (self.focused_editor == .Left) {
                                        self.focused_editor = .Right;
                                    } else {
                                        self.focused_editor = .Left;
                                    }
                                    self.refreshWindowTitle() catch {};
                                },
                                c.SDLK_n => {
                                    self.focused_widget = FocusedWidget.Autocomplete;
                                    if (self.lsp) |lsp| {
                                        const wt = self.currentWidgetTextEdit();
                                        lsp.completion(&wt.editor.buffer, wt.cursor.pos) catch |err| {
                                            std.log.err("App.editorEvents: can't send lsp request for definition: {}", .{err});
                                        };
                                    }
                                },
                                c.SDLK_k => {
                                    self.widget_lookup.reset();
                                    self.widget_lookup.setTextEdits(self.textedits) catch |err| {
                                        std.log.err("App.editorEvents: can't set WidgetLookup buffers list: {}", .{err});
                                    };
                                    if (self.has_split_view and self.focused_editor == .Right) {
                                        self.widget_lookup.list.selected_entry_idx = self.current_widget_text_edit_alt;
                                    } else {
                                        self.widget_lookup.list.selected_entry_idx = self.current_widget_text_edit;
                                    }
                                    self.focused_widget = .Lookup;
                                },
                                c.SDLK_p => {
                                    self.widget_lookup.reset();
                                    // scan directory mode
                                    self.widget_lookup.setFilepath(self.working_dir) catch |err| {
                                        std.log.err("App.editorEvents: can't set WidgetLookup filepath: {}", .{err});
                                        return;
                                    };
                                    self.widget_lookup.scanDir() catch |err| {
                                        std.log.err("App.editorEvents: can't list file in WidgetLookup: {}", .{err});
                                        return;
                                    };
                                    self.focused_widget = .Lookup;
                                },
                                c.SDLK_o => {
                                    if (shift) {
                                        self.jumpToNext() catch |err| {
                                            self.showMessageBoxError("Can't jump to next position: {}", .{err});
                                        };
                                    } else {
                                        self.jumpToPrevious() catch |err| {
                                            self.showMessageBoxError("Can't jump to previous position: {}", .{err});
                                        };
                                    }
                                },
                                c.SDLK_r => {
                                    // re-open search results, but do not reset the widget
                                    self.focused_widget = .SearchResults;
                                },
                                else => _ = self.currentWidgetTextEdit().onCtrlKeyDown(event.key.keysym.sym, ctrl, cmd),
                            }
                        }
                    },
                }
            },
            c.SDL_TEXTINPUT => {
                _ = self.currentWidgetTextEdit().onTextInput(readTextFromSDLInput(&event.text.text));
            },
            c.SDL_MOUSEWHEEL => {
                _ = self.currentWidgetTextEdit().onMouseWheel(Vec2i{ .a = event.wheel.x, .b = event.wheel.y });
            },
            c.SDL_MOUSEMOTION => {
                const mouse_coord = sdlMousePosToVec2u(event.motion.x, event.motion.y);
                var widget_pos = self.widget_text_edit_pos;
                if (self.has_split_view and self.focused_editor == .Right) {
                    widget_pos.a = self.window_scaled_size.a / 2;
                }
                self.currentWidgetTextEdit().onMouseMove(mouse_coord, widget_pos);
            },
            c.SDL_MOUSEBUTTONDOWN => {
                const mouse_coord = sdlMousePosToVec2u(event.motion.x, event.motion.y);
                var widget_pos = self.widget_text_edit_pos;
                // on click, see if we should change the editor selection
                if (self.has_split_view) {
                    if (mouse_coord.a < self.window_scaled_size.a / 2) {
                        self.focused_editor = .Left;
                    } else {
                        self.focused_editor = .Right;
                    }
                }
                if (self.has_split_view and self.focused_editor == .Right) {
                    widget_pos.a = self.window_scaled_size.a / 2;
                }
                self.currentWidgetTextEdit().onMouseStartSelection(mouse_coord, widget_pos);
            },
            c.SDL_MOUSEBUTTONUP => {
                const mouse_coord = sdlMousePosToVec2u(event.motion.x, event.motion.y);
                var widget_pos = self.widget_text_edit_pos;
                if (self.has_split_view and self.focused_editor == .Right) {
                    widget_pos.a = self.window_scaled_size.a / 2;
                }
                self.currentWidgetTextEdit().onMouseStopSelection(mouse_coord, widget_pos);
            },
            else => {},
        }
    }

    // misc
    // ----

    /// sdlMousePosToVec2u converts the mouse position in c_ints into a Vec2u
    /// If the click happened outside of the left/top window, the concerned value
    /// will be 0.
    fn sdlMousePosToVec2u(x: c_int, y: c_int) Vec2u {
        var rv = Vec2u{ .a = 0, .b = 0 };
        if (x < 0) {
            rv.a = 0;
        } else {
            rv.a = @as(usize, @intCast(x));
        }
        if (y < 0) {
            rv.b = 0;
        } else {
            rv.b = @as(usize, @intCast(y));
        }
        return rv;
    }

    /// readTextFromSDLInput reads and sizes the received text from the SDL_TEXTINPUT event.
    fn readTextFromSDLInput(sdl_text_input: []const u8) []const u8 {
        var i: usize = 0;
        while (i < sdl_text_input.len) : (i += 1) {
            if (sdl_text_input[i] == 0) {
                return sdl_text_input[0..i];
            }
        }
        return sdl_text_input[0..sdl_text_input.len];
    }
};

test "app sdlMousePosToVec2u" {
    var rv = App.sdlMousePosToVec2u(5, 15);
    try expect(rv.a == 5);
    try expect(rv.b == 15);
    rv = App.sdlMousePosToVec2u(-10, 15);
    try expect(rv.a == 0);
    try expect(rv.b == 15);
    rv = App.sdlMousePosToVec2u(5, -15);
    try expect(rv.a == 5);
    try expect(rv.b == 0);
    rv = App.sdlMousePosToVec2u(-10, -15);
    try expect(rv.a == 0);
    try expect(rv.b == 0);
}
