const std = @import("std");
const expect = std.testing.expect;

const U8Slice = @import("u8slice.zig").U8Slice;
const Vec2u = @import("vec.zig").Vec2u;
const Vec2i = @import("vec.zig").Vec2i;

pub const BufferError = error{
    OutOfBuffer,
    NoFilepath,
};

/// BufferPosition is used to refer to a position in a given buffer.
pub const BufferPosition = struct {
    fullpath: U8Slice,
    cursor_position: Vec2u,

    pub fn deinit(self: BufferPosition) void {
        self.fullpath.deinit();
    }
};

// TODO(remy): comment
pub const Buffer = struct {
    /// allocator used for all things allocated by this buffer instance.
    allocator: std.mem.Allocator,
    /// in_ram_only indicates there is not file backing this buffer storage.
    in_ram_only: bool,
    /// fullpath is the fullpath to the file backing this buffer storage.
    fullpath: U8Slice,
    /// last_modified is the mtime of the file on disk when it was last read.
    /// Used to detect external changes and trigger automatic reloads.
    last_modified: std.Io.Timestamp,
    /// auto_reload_ms is the interval (in milliseconds) between disk checks
    /// for this buffer. A value of 0 disables automatic reload for this buffer
    /// entirely (the user declined a reload confirmation once).
    auto_reload_ms: u32,
    /// lines is the content of this Buffer.
    lines: std.ArrayList(U8Slice),

    // Constructors
    // ------------

    /// init_empty initializes an empty buffer.
    /// Creates an initial first line.
    pub fn initEmpty(allocator: std.mem.Allocator) !Buffer {
        const empty_line = U8Slice.initEmpty(allocator);
        var buff = Buffer{
            .allocator = allocator,
            .in_ram_only = true,
            .fullpath = U8Slice.initEmpty(allocator),
            .last_modified = .zero,
            .auto_reload_ms = 500,
            .lines = std.ArrayList(U8Slice).empty,
        };
        try buff.lines.append(allocator, empty_line);
        return buff;
    }

    /// appendLinesFromFile reads the whole content of `file` and appends one
    /// U8Slice per line to `lines`. Each line keeps its trailing '\n'.
    /// A Buffer always contains at least one line, so reading an empty file
    /// appends a single empty line.
    // NOTE(remy): should we consider using an ArenaAllocator to read the file?
    // (using stats first to know file size)
    fn appendLinesFromFile(
        allocator: std.mem.Allocator,
        io: std.Io,
        file: std.Io.File,
        lines: *std.ArrayList(U8Slice),
    ) !void {
        const block_size = 4096;
        var slice: [block_size]u8 = undefined;
        var read: usize = block_size;

        var u8slice = U8Slice.initEmpty(allocator);

        // TODO(remy): what about performances? test with different block_size on large files
        while (read == block_size) {
            var i: usize = 0;
            var last_append: usize = 0;

            const buffers = [_][]u8{slice[0..]};
            // the end of the stream is signalled with error.EndOfStream, it is
            // not a failure: stop reading there, the data read so far is complete.
            read = file.readStreaming(io, &buffers) catch |err| switch (err) {
                error.EndOfStream => 0,
                else => return err,
            };

            while (i < read) : (i += 1) {
                if (slice[i] == '\n') {
                    // append the data left until the \n with the \n included
                    try u8slice.appendConst(slice[last_append .. i + 1]); // allocate the data in an u8slice
                    // append the line in the lines list of the buffer
                    try lines.append(allocator, u8slice);
                    // move the cursor in this buffer
                    last_append = i + 1;
                    // recreate a new u8slice to work with for next lines
                    u8slice = U8Slice.initEmpty(allocator);
                }
            }
            // append the rest of the read buffer
            try u8slice.appendConst(slice[last_append..read]);
        }

        // we completely read the file, if the buffer isn't empty, it means we have
        // dangling data, append it to the buffer.
        if (!u8slice.isEmpty()) {
            try lines.append(allocator, u8slice);
        }

        // a file without any content has no line at all: like initEmpty does, a
        // Buffer always has at least one line, create it here.
        if (lines.items.len == 0) {
            try lines.append(allocator, U8Slice.initEmpty(allocator));
        }
    }

    /// initFromFile creates a buffer, reads data from the given fullpath
    /// and copies it in the Buffer instance.
    /// initFromFile calls `trackLineReturnPositions` to start tracking the line returns.
    // TODO(remy): some refactoring (see `App.peekLine`) would be nice here.
    pub fn initFromFile(allocator: std.mem.Allocator, io: std.Io, filepath: []const u8) !Buffer {
        // make sure that the provided fullpath is absolute
        const path = try std.Io.Dir.cwd().realPathFileAlloc(io, filepath, allocator);
        defer allocator.free(path);
        var fullpath = U8Slice.initEmpty(allocator);
        try fullpath.appendConst(path);

        var rv = Buffer{
            .allocator = allocator,
            .in_ram_only = false,
            .fullpath = fullpath,
            .last_modified = .zero,
            .auto_reload_ms = 500,
            .lines = std.ArrayList(U8Slice).empty,
        };

        rv.in_ram_only = false;

        var file = try std.Io.Dir.cwd().openFile(io, filepath, .{});
        defer file.close(io);

        // read the file
        try appendLinesFromFile(allocator, io, file, &rv.lines);

        // capture the modification time of the file on disk so that we can
        // detect later changes and auto-reload if needed.
        const stat = std.Io.Dir.cwd().statFile(io, filepath, .{}) catch |err| {
            std.log.err("Buffer.initFromFile: can't stat {s}: {}", .{ filepath, err });
            return err;
        };
        rv.last_modified = stat.mtime;

        return rv;
    }

    /// writeOnDisk stores the buffer data in the file (in `fullpath`).
    pub fn writeOnDisk(self: *Buffer, io: std.Io) !void {
        if (self.in_ram_only) {
            return;
        }
        if (self.fullpath.size() == 0) {
            return BufferError.NoFilepath;
        }

        // check if the file exists, if not, try creating it
        // TODO(remy): use a tmp file and mv at the end instead
        var file = try std.Io.Dir.cwd().createFile(io, self.fullpath.bytes(), .{ .truncate = true });
        // at this point, the file is opened, defer closing it.
        defer file.close(io);

        for (self.lines.items) |line| {
            try file.writeStreamingAll(io, line.bytes());
        }
        try file.sync(io);
        self.in_ram_only = false;

        // refresh the last_modified time to avoid a spurious auto-reload right
        // after a save.
        const stat = std.Io.Dir.cwd().statFile(io, self.fullpath.bytes(), .{}) catch |err| {
            std.log.err("Buffer.writeOnDisk: can't stat {s}: {}", .{ self.fullpath.bytes(), err });
            return err;
        };
        self.last_modified = stat.mtime;
    }

    /// reload reloads the buffer from disk, discarding any unsaved changes.
    pub fn reload(self: *Buffer, io: std.Io) !void {
        if (self.in_ram_only) {
            return;
        }
        if (self.fullpath.size() == 0) {
            return BufferError.NoFilepath;
        }

        // Clear existing lines
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.clearRetainingCapacity();

        // Read the file again
        const filepath = self.fullpath.bytes();
        var file = try std.Io.Dir.cwd().openFile(io, filepath, .{});
        defer file.close(io);

        try appendLinesFromFile(self.allocator, io, file, &self.lines);

        // update the modification time to reflect what we just read from disk.
        const stat = std.Io.Dir.cwd().statFile(io, filepath, .{}) catch |err| {
            std.log.err("Buffer.reload: can't stat {s}: {}", .{ filepath, err });
            return err;
        };
        self.last_modified = stat.mtime;
    }

    pub fn deinit(self: *Buffer) void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit(self.allocator);
        self.fullpath.deinit();
    }

    // Methods
    // -------

    /// getLine returns a pointer in the buffer to a given line.
    /// `line_number` starts with 0.
    /// Returns a pointer for the caller to be able to modify the line, however, the
    /// pointer should never be null.
    pub fn getLine(self: Buffer, line_number: usize) !*U8Slice {
        if (line_number + 1 > self.lines.items.len) {
            return BufferError.OutOfBuffer;
        }
        return &self.lines.items[line_number];
    }

    pub fn deleteLine(self: *Buffer, line_number: usize) !U8Slice {
        if (line_number + 1 > self.lines.items.len) {
            return BufferError.OutOfBuffer;
        }
        return self.lines.orderedRemove(line_number);
    }

    /// longestLine returns the size of the longest line in the lines visible
    /// between the given interval.
    pub fn longestLine(self: *Buffer, line_start: usize, line_end: usize) !usize {
        if (line_start >= self.lines.items.len) {
            return 0;
        }

        var rv: usize = 0;
        var i: usize = line_start;

        while (i < line_end) : (i += 1) {
            if (i < self.lines.items.len) {
                if (self.getLine(i)) |line| {
                    const utf8size = try line.utf8size();
                    rv = @max(utf8size, rv);
                } else |_| {}
            }
        }

        return rv;
    }

    /// linesCount returns how many lines is this buffer containing.
    pub fn linesCount(self: Buffer) usize {
        return self.lines.items.len;
    }

    /// fulltext returns all the text of the buffer in one U8Slice.
    /// Callers has to manage the U8Slice memory.
    // TODO(remy): add line_start and line_end
    // TODO(remy): test
    pub fn fulltext(self: Buffer) !U8Slice {
        var rv = U8Slice.initEmpty(self.allocator);
        for (self.lines.items) |line| {
            try rv.appendConst(line.bytes());
        }
        return rv;
    }
};

test "buffer init_empty" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initEmpty(allocator);
    try expect(buffer.lines.items.len == 1);
    try expect(buffer.fullpath.isEmpty() == true);
    try expect(buffer.in_ram_only == true);
    buffer.deinit();
}

test "buffer init_from_file" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var working_dir = U8Slice.initEmpty(allocator);
    defer working_dir.deinit();
    // read cwd
    const working_path = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", allocator);
    defer allocator.free(working_path);
    try working_dir.appendConst(working_path);

    var fullpath = U8Slice.initEmpty(allocator);
    defer fullpath.deinit();

    try fullpath.appendConst(working_dir.bytes());
    try fullpath.appendConst("/");
    var copy = try fullpath.copy(allocator);
    defer copy.deinit();

    try fullpath.appendConst("tests/sample_1");
    var buffer = try Buffer.initFromFile(allocator, io, "tests/sample_1");
    try expect(buffer.in_ram_only == false);
    try expect(buffer.lines.items.len == 1);
    try expect(std.mem.eql(u8, buffer.fullpath.bytes(), fullpath.bytes()));
    try expect(std.mem.eql(u8, buffer.lines.items[0].bytes(), "hello world\n"));
    buffer.deinit();

    try copy.appendConst("tests/sample_2");
    buffer = try Buffer.initFromFile(allocator, io, "tests/sample_2");
    try expect(buffer.in_ram_only == false);
    try expect(buffer.lines.items.len == 3);
    try expect(std.mem.eql(u8, buffer.fullpath.bytes(), copy.bytes()));
    try expect(std.mem.eql(u8, buffer.lines.items[0].bytes(), "hello world\n"));
    try expect(std.mem.eql(u8, buffer.lines.items[1].bytes(), "and a second line\n"));
    try expect(std.mem.eql(u8, buffer.lines.items[2].bytes(), "and a third"));
    buffer.deinit();
}

test "buffer longest_line" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var buffer = try Buffer.initFromFile(allocator, io, "tests/sample_1");
    try std.testing.expectEqual(buffer.longestLine(0, buffer.lines.items.len), 12);
    buffer.deinit();
    buffer = try Buffer.initFromFile(allocator, io, "tests/sample_3");
    try std.testing.expectEqual(buffer.longestLine(0, buffer.lines.items.len), 9);
    buffer.deinit();
    buffer = try Buffer.initFromFile(allocator, io, "tests/sample_5");
    try std.testing.expectEqual(buffer.longestLine(3, 5), 71);
    buffer.deinit();
}

test "buffer write_file" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var buffer_first = try Buffer.initFromFile(allocator, io, "tests/sample_5");

    // read it and write it in a different file
    var buffer_second = try Buffer.initFromFile(allocator, io, "tests/sample_5");
    buffer_second.fullpath.deinit();
    buffer_second.fullpath = try U8Slice.initFromSlice(allocator, "tests/sample_5_test");
    try buffer_second.writeOnDisk(io);

    // close it, read the newly created file
    buffer_second.deinit();
    buffer_second = try Buffer.initFromFile(allocator, io, "tests/sample_5_test");

    // validate that it contains the correct data
    try std.testing.expectEqual(buffer_first.lines.items.len, buffer_second.lines.items.len);

    var i: usize = 0;
    while (i < buffer_first.lines.items.len) : (i += 1) {
        var left_line = buffer_first.getLine(i) catch {
            try expect(true == false);
            return;
        };
        var right_line = buffer_second.getLine(i) catch {
            try expect(true == false);
            return;
        };
        try std.testing.expectEqualSlices(u8, left_line.bytes(), right_line.bytes());
    }

    // remove the temporary file
    try std.Io.Dir.deleteFileAbsolute(io, buffer_second.fullpath.bytes());

    buffer_first.deinit();
    buffer_second.deinit();
}

test "buffer getLine" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var buffer = try Buffer.initFromFile(allocator, io, "tests/sample_2");
    defer buffer.deinit();

    // two get should always return the same pointer
    const first_time = try buffer.getLine(0);
    const second_time = try buffer.getLine(0);

    try std.testing.expectEqual(first_time, second_time);
    try std.testing.expectEqualStrings("hello world\n", first_time.bytes());
    try std.testing.expectEqualStrings("hello world\n", second_time.bytes());

    var line = try buffer.getLine(1);
    try std.testing.expectEqualStrings("and a second line\n", line.bytes());
    line = try buffer.getLine(2);
    try std.testing.expectEqualStrings("and a third", line.bytes());

    // can't get more than what's in the buffer
    try std.testing.expectError(BufferError.OutOfBuffer, buffer.getLine(3));
    try std.testing.expectError(BufferError.OutOfBuffer, buffer.getLine(100));
}

test "buffer reload updates content and last_modified" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const filepath = "tests/sample_reload_test";

    // write an initial version of the file
    {
        var file = try std.Io.Dir.cwd().createFile(io, filepath, .{ .truncate = true });
        defer file.close(io);
        try file.writeStreamingAll(io, "first version\n");
    }

    // open a buffer from the file, capturing its mtime
    var buffer = try Buffer.initFromFile(allocator, io, filepath);
    defer buffer.deinit();
    const original_mtime = buffer.last_modified;
    try expect(buffer.lines.items.len == 1);
    try std.testing.expectEqualStrings("first version\n", buffer.lines.items[0].bytes());

    // auto_reload_ms is enabled (non-zero) by default
    try expect(buffer.auto_reload_ms != 0);

    // modify the file on disk
    {
        var file = try std.Io.Dir.cwd().createFile(io, filepath, .{ .truncate = true });
        defer file.close(io);
        try file.writeStreamingAll(io, "second version\n");
    }

    // reload the buffer
    try buffer.reload(io);
    try expect(buffer.lines.items.len == 1);
    try std.testing.expectEqualStrings("second version\n", buffer.lines.items[0].bytes());

    // the mtime should have been refreshed after the reload
    const new_mtime = buffer.last_modified;
    try expect(new_mtime.nanoseconds != original_mtime.nanoseconds);

    // remove the temporary file
    const abs_path = try std.Io.Dir.cwd().realPathFileAlloc(io, filepath, allocator);
    defer allocator.free(abs_path);
    try std.Io.Dir.deleteFileAbsolute(io, abs_path);
}

test "buffer init_from_an_empty_file" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const filepath = "tests/sample_empty_file_test";

    // create a file without any content
    {
        var file = try std.Io.Dir.cwd().createFile(io, filepath, .{ .truncate = true });
        defer file.close(io);
    }

    // even empty, a buffer always contains at least one line.
    var buffer = try Buffer.initFromFile(allocator, io, filepath);
    errdefer buffer.deinit();
    try expect(buffer.lines.items.len == 1);
    try std.testing.expectEqualStrings("", buffer.lines.items[0].bytes());

    // and reloading an empty file keeps one empty line too.
    try buffer.reload(io);
    try expect(buffer.lines.items.len == 1);
    try std.testing.expectEqualStrings("", buffer.lines.items[0].bytes());

    buffer.deinit();

    // remove the temporary file
    const abs_path = try std.Io.Dir.cwd().realPathFileAlloc(io, filepath, allocator);
    defer allocator.free(abs_path);
    try std.Io.Dir.deleteFileAbsolute(io, abs_path);
}

test "buffer init_from_a_file_ending_on_a_block_boundary" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const block_size = 4096;

    const filepath = "tests/sample_block_size_test";

    // a file whose size is an exact multiple of the block size used to read it,
    // the last line ends with a line return.
    {
        const content = try allocator.alloc(u8, block_size);
        defer allocator.free(content);
        @memset(content[0 .. block_size - 1], 'a');
        content[block_size - 1] = '\n';
        var file = try std.Io.Dir.cwd().createFile(io, filepath, .{ .truncate = true });
        defer file.close(io);
        try file.writeStreamingAll(io, content);

        var buffer = try Buffer.initFromFile(allocator, io, filepath);
        defer buffer.deinit();
        try expect(buffer.lines.items.len == 1);
        try expect(buffer.lines.items[0].size() == block_size);
    }

    // same size, but this time the last line has no line return.
    {
        const content = try allocator.alloc(u8, block_size);
        defer allocator.free(content);
        @memset(content, 'a');
        var file = try std.Io.Dir.cwd().createFile(io, filepath, .{ .truncate = true });
        defer file.close(io);
        try file.writeStreamingAll(io, content);

        var buffer = try Buffer.initFromFile(allocator, io, filepath);
        defer buffer.deinit();
        try expect(buffer.lines.items.len == 1);
        try expect(buffer.lines.items[0].size() == block_size);
    }

    // over one block, with lines spanning across the block boundaries.
    {
        var content = std.ArrayList(u8).empty;
        defer content.deinit(allocator);
        var i: usize = 0;
        while (i < block_size * 3) : (i += 1) {
            try content.append(allocator, if (i % 10 == 9) '\n' else 'x');
        }
        var file = try std.Io.Dir.cwd().createFile(io, filepath, .{ .truncate = true });
        defer file.close(io);
        try file.writeStreamingAll(io, content.items);

        var buffer = try Buffer.initFromFile(allocator, io, filepath);
        defer buffer.deinit();
        // 1228 complete lines, plus a last one of 8 bytes without a line return.
        try expect(buffer.lines.items.len == block_size * 3 / 10 + 1);
        try expect(buffer.lines.items[0].size() == 10);
        try std.testing.expectEqualStrings("xxxxxxxxx\n", buffer.lines.items[0].bytes());
        // the line spanning over the first and the second blocks is complete.
        try expect(buffer.lines.items[408].size() == 10);
        try std.testing.expectEqualStrings("xxxxxxxxx\n", buffer.lines.items[408].bytes());
        // and the last line, without a line return, is there.
        try std.testing.expectEqualStrings("xxxxxxxx", buffer.lines.items[1228].bytes());
    }

    // remove the temporary file
    const abs_path = try std.Io.Dir.cwd().realPathFileAlloc(io, filepath, allocator);
    defer allocator.free(abs_path);
    try std.Io.Dir.deleteFileAbsolute(io, abs_path);
}
